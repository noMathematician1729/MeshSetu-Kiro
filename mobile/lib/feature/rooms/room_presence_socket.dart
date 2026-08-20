import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'room_presence.dart';

/// Live room membership shared through the event backend. Mesh announcements
/// remain durable/offline fallback; this channel makes open lobbies update
/// immediately when a participant joins or leaves.
class RoomPresenceSocket {
  RoomPresenceSocket({
    required this.baseUrl,
    required this.gatewayKey,
    required this.siteId,
    required this.roomId,
    required this.memberId,
    required this.displayName,
  });

  final Uri baseUrl;
  final String gatewayKey;
  final String siteId;
  final String roomId;
  final String memberId;
  final String displayName;
  final _members = StreamController<List<RoomMember>>.broadcast();
  WebSocket? _socket;
  Timer? _retry;
  bool _disposed = false;
  bool _connecting = false;

  Stream<List<RoomMember>> get members => _members.stream;

  void start() => unawaited(_connect());

  Future<void> _connect() async {
    if (_disposed || _connecting || _socket != null) return;
    _connecting = true;
    try {
      final endpoint = baseUrl.resolve('/v1/rooms/stream');
      final uri = endpoint.replace(
        scheme: endpoint.scheme == 'https' ? 'wss' : 'ws',
      );
      final socket = await WebSocket.connect(uri.toString());
      if (_disposed) {
        await socket.close();
        return;
      }
      _socket = socket;
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
      socket.listen(
        _onMessage,
        onDone: _scheduleReconnect,
        onError: (_, __) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);
      if (decoded is! Map || decoded['type'] != 'room-members') return;
      final data = decoded['data'];
      if (data is! List) return;
      final values = <RoomMember>[
        for (final item in data)
          if (item is Map)
            if (RoomPresenceCodec.fromJson(item.cast<String, Object?>())
                case final member?)
              member,
      ]..sort((a, b) => a.joinedAtMs.compareTo(b.joinedAtMs));
      if (!_disposed) _members.add(values);
    } catch (_) {
      // Ignore malformed presence data and wait for the next snapshot.
    }
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
    await _socket?.close();
    _socket = null;
    await _members.close();
  }
}
