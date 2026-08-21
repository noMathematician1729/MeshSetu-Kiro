import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'room_presence.dart';

class LiveRoomMessage {
  const LiveRoomMessage({
    required this.messageId,
    required this.text,
    required this.memberId,
    required this.displayName,
    required this.sentAtMs,
  });

  final String messageId;
  final String text;
  final String memberId;
  final String displayName;
  final int sentAtMs;
}

/// A transport [RoomMessageDispatcher] can attempt a room message over
/// before falling back to the durable mesh outbox. [RoomPresenceSocket] is
/// the only implementation today; the interface exists so the dispatcher
/// can be tested without a real socket/server.
abstract interface class LiveRoomMessageTransport {
  /// Whether the live channel currently has a snapshot showing at least one
  /// *other* room member online. A lone sender has nobody to deliver to, so
  /// the dispatcher should go straight to the mesh instead of waiting on a
  /// socket round trip that can only fail.
  bool get canReachOtherMember;

  /// Sends [text] over the live channel and resolves `true` only once the
  /// server confirms at least one other member received it, `false` if the
  /// channel is unreachable, the send fails, or no confirmation arrives
  /// within the transport's ack timeout.
  Future<bool> sendRoomMessage({required String messageId, required String text});
}

/// Live room membership shared through the event backend. Mesh announcements
/// remain durable/offline fallback; this channel makes open lobbies update
/// immediately when a participant joins or leaves.
class RoomPresenceSocket implements LiveRoomMessageTransport {
  RoomPresenceSocket({
    required this.baseUrl,
    required this.gatewayKey,
    required this.siteId,
    required this.roomId,
    required this.memberId,
    required this.displayName,
    this.messageAckTimeout = const Duration(seconds: 5),
  });

  final Uri baseUrl;
  final String gatewayKey;
  final String siteId;
  final String roomId;
  final String memberId;
  final String displayName;

  /// How long [sendRoomMessage] waits for a `room-message-accepted` reply
  /// before treating the send as failed and letting the caller fall back to
  /// the mesh. Overridable in tests so they don't wait out a real timeout.
  final Duration messageAckTimeout;

  final _members = StreamController<List<RoomMember>>.broadcast();
  final _messages = StreamController<LiveRoomMessage>.broadcast();
  final _debug = StreamController<String>.broadcast();
  final _pendingMessages = <Map<String, Object?>>[];
  final Map<String, Completer<int>> _pendingAcks = {};
  WebSocket? _socket;
  Timer? _retry;
  bool _disposed = false;
  bool _connecting = false;
  bool _canReachOtherMember = false;

  Stream<List<RoomMember>> get members => _members.stream;
  Stream<LiveRoomMessage> get messages => _messages.stream;
  Stream<String> get debug => _debug.stream;

  @override
  bool get canReachOtherMember => _canReachOtherMember;

  void start() => unawaited(_connect());

  Future<void> _connect() async {
    if (_disposed || _connecting || _socket != null) return;
    _connecting = true;
    try {
      final endpoint = baseUrl.resolve('/v1/rooms/stream');
      final uri = endpoint.replace(
        scheme: endpoint.scheme == 'https' ? 'wss' : 'ws',
      );
      _report('Connecting to ${uri.host}…');
      final socket = await WebSocket.connect(uri.toString());
      if (_disposed) {
        await socket.close();
        return;
      }
      _socket = socket;
      _report('Connected; joining live room…');
      socket.add(
        jsonEncode({
          'type': 'join-room',
          'siteId': siteId,
          'roomId': roomId,
          'memberId': memberId,
          'displayName': displayName,
          'gatewayKey': gatewayKey,
        }),
      );
      for (final message in _pendingMessages) {
        socket.add(jsonEncode(message));
      }
      _pendingMessages.clear();
      socket.listen(
        _onMessage,
        onDone: () {
          _report('Disconnected; retrying…');
          _scheduleReconnect();
        },
        onError: (_, __) {
          _report('Socket error; retrying…');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _report('Connection failed; retrying…');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);
      if (decoded is! Map) return;
      if (decoded['type'] == 'room-joined') {
        _report('Joined live room.');
        return;
      }
      if (decoded['type'] == 'room-message') {
        final data = decoded['data'];
        if (data is! Map) return;
        final item = data.cast<String, Object?>();
        final messageId = item['messageId'] as String?;
        final text = item['text'] as String?;
        final memberId = item['memberId'] as String?;
        final displayName = item['displayName'] as String?;
        final sentAtMs = (item['sentAtMs'] as num?)?.toInt();
        if (messageId == null ||
            text == null ||
            memberId == null ||
            displayName == null ||
            sentAtMs == null) {
          return;
        }
        if (!_disposed) {
          _messages.add(
            LiveRoomMessage(
              messageId: messageId,
              text: text,
              memberId: memberId,
              displayName: displayName,
              sentAtMs: sentAtMs,
            ),
          );
          _report('Received live message from $displayName.');
        }
        return;
      }
      if (decoded['type'] == 'room-message-accepted') {
        final data = decoded['data'];
        if (data is! Map) return;
        final item = data.cast<String, Object?>();
        final messageId = item['messageId'] as String?;
        final recipientCount = (item['recipientCount'] as num?)?.toInt();
        if (messageId == null || recipientCount == null) return;
        final pending = _pendingAcks.remove(messageId);
        if (pending != null && !pending.isCompleted) {
          pending.complete(recipientCount);
        }
        return;
      }
      if (decoded['type'] != 'room-members') return;
      final data = decoded['data'];
      if (data is! List) return;
      final values = <RoomMember>[
        for (final item in data)
          if (item is Map)
            if (RoomPresenceCodec.fromJson(item.cast<String, Object?>())
                case final member?)
              member,
      ]..sort((a, b) => a.joinedAtMs.compareTo(b.joinedAtMs));
      _canReachOtherMember = values.any(
        (member) => member.memberId != memberId,
      );
      if (!_disposed) _members.add(values);
    } catch (_) {
      // Ignore malformed presence data and wait for the next snapshot.
    }
  }

  @override
  Future<bool> sendRoomMessage({
    required String messageId,
    required String text,
  }) async {
    final message = <String, Object?>{
      'type': 'room-message',
      'messageId': messageId,
      'text': text,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    final socket = _socket;
    if (socket == null) {
      _pendingMessages.add(message);
      _report('Queued message until live chat connects.');
      return false;
    }
    final ack = _pendingAcks[messageId] ??= Completer<int>();
    socket.add(jsonEncode(message));
    _report('Sent message to live room.');
    try {
      final recipientCount = await ack.future.timeout(messageAckTimeout);
      return recipientCount > 0;
    } on TimeoutException {
      _report('No live-room acknowledgement; falling back to mesh.');
      return false;
    } finally {
      _pendingAcks.remove(messageId);
    }
  }

  void _report(String value) {
    if (!_disposed) _debug.add(value);
  }

  void _scheduleReconnect() {
    _socket = null;
    if (_disposed || _retry != null) return;
    _retry = Timer(const Duration(seconds: 3), () {
      _retry = null;
      unawaited(_connect());
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    for (final pending in _pendingAcks.values) {
      if (!pending.isCompleted) pending.complete(0);
    }
    _pendingAcks.clear();
    await _socket?.close();
    _socket = null;
    await _members.close();
    await _messages.close();
    await _debug.close();
  }
}
