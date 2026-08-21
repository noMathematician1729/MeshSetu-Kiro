import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/database.dart';
import '../../core/model/model.dart';
import 'room_message_packet.dart';
import 'room_policy.dart';
import 'room_presence.dart';

const _uuid = Uuid();

/// Per-message delivery state surfaced in the chat UI (Task 6). Derived from
/// `outboxEvents.state` for messages this device sent; always [delivered]
/// for messages received from a peer (mesh or socket), since arrival at all
/// implies delivery.
enum RoomMessageState { queued, sending, delivered, failed }

RoomMessageState _stateFromOutboxState(String state) => switch (state) {
  RoomRepository.socketPendingState => RoomMessageState.sending,
  'relaying' => RoomMessageState.sending,
  'acked' => RoomMessageState.delivered,
  'expired' || 'failed' => RoomMessageState.failed,
  _ => RoomMessageState.queued, // 'created', 'ready'/meshReadyState, 'retry'
};

class RoomMessage {
  const RoomMessage({
    required this.eventId,
    required this.text,
    required this.fromPeerId,
    required this.atMs,
    required this.mine,
    this.state = RoomMessageState.delivered,
  });

  final String eventId;
  final String text;
  final String? fromPeerId;
  final int atMs;
  final bool mine;

  /// Only meaningful when [mine] is true; a received message is always
  /// [RoomMessageState.delivered] because its presence in the inbox already
  /// proves it arrived.
  final RoomMessageState state;
}

/// `feature/rooms`: composes/reads Room chat, enforcing [RoomPolicy] before
/// a message is allowed onto the durable outbox (Bible §10.2/§10.3 — SOS
/// itself never routes through here, it transcends Room ACL).
class RoomRepository {
  RoomRepository(this._db, {required this.siteId});

  final MeshDatabase _db;
  final String siteId;

  /// A message that [RoomMessageDispatcher] is about to attempt over the
  /// live internet socket. Not yet eligible for the mesh outbox drain
  /// ([OutboxSender] only watches `ready`/`retry` rows) so a socket attempt
  /// and a GATT send never race for the same event.
  static const String socketPendingState = 'socket_pending';

  /// A message that should be drained onto the mesh outbox immediately —
  /// either because no live socket peer was reachable, or because a socket
  /// attempt for it failed. Equivalent to the durable-outbox `ready` state.
  static const String meshReadyState = 'ready';

  Future<String> sendMessage({
    required RoomPolicy policy,
    required Set<String> userRoles,
    required String text,
    String initialState = meshReadyState,
  }) async {
    if (!canSend(policy, userRoles)) {
      throw StateError('not authorized to send in ${policy.roomId}');
    }
    final message = text.trim();
    if (message.isEmpty) throw StateError('message must not be empty');
    final textBytes = utf8.encode(message).length;
    if (textBytes > policy.maxMessageBytes) {
      throw StateError(
        'message is $textBytes bytes; ${policy.roomId} allows '
        '${policy.maxMessageBytes}',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final eventId = _uuid.v4();
    final packet = RoomMessagePacketCodec.encode(
      siteId: siteId,
      roomId: policy.roomId,
      eventId: eventId,
      text: message,
    );
    await _db
        .into(_db.outboxEvents)
        .insert(
          OutboxEventsCompanion.insert(
            eventId: eventId,
            objectId: Value(_randomObjectId()),
            siteId: siteId,
            roomId: policy.roomId,
            payloadType: PayloadType.roomMessage.name,
            rawText: Value(message),
            priority: PriorityBand.p2Normal.name,
            payload: Value(packet),
            state: Value(initialState),
            createdAtMs: now,
            updatedAtMs: now,
            expiresAtMs: now + policy.ttlSeconds * 1000,
          ),
        );
    return eventId;
  }

  /// Marks a [socketPendingState] row as delivered without ever entering the
  /// mesh outbox — the internet socket already confirmed a remote member
  /// received it, so a GATT send would be redundant.
  Future<void> markSocketDelivered(String eventId) async {
    await _db.markState(eventId, 'acked', DateTime.now().millisecondsSinceEpoch);
  }

  /// Moves a [socketPendingState] row into the mesh outbox after a socket
  /// delivery attempt failed (or was never attempted). [OutboxSender] picks
  /// up [meshReadyState] rows on its next watch tick.
  Future<void> queueForMesh(String eventId) async {
    await _db.markState(
      eventId,
      meshReadyState,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Persists a message that arrived over the live internet socket rather
  /// than the mesh. Stored directly in the inbox (never touches the mesh
  /// outbox/relay) so it renders next to mesh-delivered messages in [watch].
  /// [objectId] is derived deterministically from [eventId] (rather than
  /// [_randomObjectId]) because `inboxEvents.objectId` is the actual primary
  /// key: a duplicate socket delivery of the same [eventId] must resolve to
  /// the same row via `insertOnConflictUpdate`, not create a second one.
  Future<void> storeSocketMessage({
    required String roomId,
    required String eventId,
    required String text,
    required String fromPeerId,
    required int sentAtMs,
  }) async {
    await _db.insertInbox(
      InboxEventsCompanion.insert(
        objectId: Value(_objectIdForEventId(eventId)),
        eventId: eventId,
        siteId: siteId,
        roomId: roomId,
        payloadType: PayloadType.roomMessage.name,
        payload: Uint8List.fromList(utf8.encode(text)),
        peerId: fromPeerId,
        receivedAtMs: sentAtMs,
      ),
    );
  }

  Future<void> announceMember({
    required String roomId,
    required String memberId,
    required String displayName,
  }) async {
    if (roomId.trim().isEmpty ||
        memberId.trim().isEmpty ||
        displayName.trim().isEmpty) {
      throw ArgumentError('room and member identity must not be blank');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final member = RoomMember(
      memberId: memberId,
      displayName: displayName.trim(),
      joinedAtMs: now,
    );
    await _db
        .into(_db.outboxEvents)
        .insert(
          OutboxEventsCompanion.insert(
            eventId: _uuid.v4(),
            objectId: Value(_randomObjectId()),
            siteId: siteId,
            roomId: roomId,
            payloadType: PayloadType.responderUpdate.name,
            rawText: Value(member.displayName),
            priority: PriorityBand.p1High.name,
            payload: Value(RoomPresenceCodec.encode(member)),
            state: const Value('ready'),
            createdAtMs: now,
            updatedAtMs: now,
            expiresAtMs: now + const Duration(hours: 24).inMilliseconds,
          ),
        );
  }

  Stream<List<RoomMessage>> watch({
    required RoomPolicy policy,
    required Set<String> userRoles,
  }) {
    if (!canRead(policy, userRoles)) {
      return Stream.error(
        StateError('not authorized to read ${policy.roomId}'),
      );
    }
    final roomId = policy.roomId;
    return Stream.multi((controller) {
      var closed = false;
      var loading = false;
      var refreshQueued = false;

      Future<void> refresh() async {
        if (closed) return;
        if (loading) {
          refreshQueued = true;
          return;
        }
        loading = true;
        try {
          final sentRows =
              await (_db.select(_db.outboxEvents)..where(
                    (t) => t.siteId.equals(siteId) & t.roomId.equals(roomId),
                  ))
                  .get();
          final receivedRows =
              await (_db.select(_db.inboxEvents)..where(
                    (t) => t.siteId.equals(siteId) & t.roomId.equals(roomId),
                  ))
                  .get();
          final messages = [
            for (final r in sentRows)
              if (r.payloadType == PayloadType.roomMessage.name)
                RoomMessage(
                  eventId: r.eventId,
                  text: r.rawText ?? '',
                  fromPeerId: null,
                  atMs: r.createdAtMs,
                  mine: true,
                  state: _stateFromOutboxState(r.state),
                ),
            for (final r in receivedRows)
              if (r.payloadType == PayloadType.roomMessage.name)
                if (_decodeMessage(r) case final message?) message,
          ]..sort((a, b) => a.atMs.compareTo(b.atMs));
          if (!closed) controller.add(messages);
        } finally {
          loading = false;
          if (refreshQueued) {
            refreshQueued = false;
            unawaited(refresh());
          }
        }
      }

      final sentSub = _db.watchRoom(siteId, roomId).listen((_) {
        unawaited(refresh());
      });
      final receivedSub = _db.watchInboxRoom(siteId, roomId).listen((_) {
        unawaited(refresh());
      });
      controller.onCancel = () async {
        closed = true;
        await sentSub.cancel();
        await receivedSub.cancel();
      };
      unawaited(refresh());
    });
  }

  Stream<List<RoomMember>> watchMembers(String roomId) {
    return Stream.multi((controller) {
      var closed = false;
      var loading = false;
      var refreshQueued = false;

      Future<void> refresh() async {
        if (closed) return;
        if (loading) {
          refreshQueued = true;
          return;
        }
        loading = true;
        try {
          final sentRows =
              await (_db.select(_db.outboxEvents)..where(
                    (t) => t.siteId.equals(siteId) & t.roomId.equals(roomId),
                  ))
                  .get();
          final receivedRows =
              await (_db.select(_db.inboxEvents)..where(
                    (t) => t.siteId.equals(siteId) & t.roomId.equals(roomId),
                  ))
                  .get();
          final members = <String, RoomMember>{};
          for (final row in sentRows) {
            if (row.payloadType != PayloadType.responderUpdate.name ||
                row.payload == null) {
              continue;
            }
            final member = RoomPresenceCodec.decode(row.payload!);
            if (member != null) members[member.memberId] = member;
          }
          for (final row in receivedRows) {
            if (row.payloadType != PayloadType.responderUpdate.name) continue;
            final member = RoomPresenceCodec.decode(row.payload);
            if (member != null) members[member.memberId] = member;
          }
          final values = members.values.toList()
            ..sort((a, b) => a.joinedAtMs.compareTo(b.joinedAtMs));
          if (!closed) controller.add(values);
        } finally {
          loading = false;
          if (refreshQueued) {
            refreshQueued = false;
            unawaited(refresh());
          }
        }
      }

      final sentSub = _db.watchRoom(siteId, roomId).listen((_) {
        unawaited(refresh());
      });
      final receivedSub = _db.watchInboxRoom(siteId, roomId).listen((_) {
        unawaited(refresh());
      });
      controller.onCancel = () async {
        closed = true;
        await sentSub.cancel();
        await receivedSub.cancel();
      };
      unawaited(refresh());
    });
  }

  int _randomObjectId() {
    final random = Random.secure();
    final high = random.nextInt(1 << 31);
    final low = random.nextInt(1 << 32);
    final value = (high << 32) | low;
    return value == 0 ? 1 : value;
  }

  /// Stable, non-zero signed 64-bit id derived from [eventId] so repeated
  /// socket deliveries of the same message always target the same
  /// `inboxEvents` primary-key row.
  int _objectIdForEventId(String eventId) {
    final digest = sha256.convert(utf8.encode(eventId)).bytes;
    final value = ByteData.sublistView(
      Uint8List.fromList(digest.sublist(0, 8)),
    ).getInt64(0, Endian.big);
    return value == 0 ? 1 : value;
  }

  RoomMessage? _decodeMessage(InboxEvent row) {
    try {
      final text = RoomMessagePacketCodec.isEncoded(row.payload)
          ? RoomMessagePacketCodec.decode(
              siteId: row.siteId,
              roomId: row.roomId,
              eventId: row.eventId,
              packet: row.payload,
            )
          : utf8.decode(row.payload, allowMalformed: false);
      return RoomMessage(
        eventId: row.eventId,
        text: text,
        fromPeerId: row.peerId,
        atMs: row.receivedAtMs,
        mine: false,
      );
    } catch (_) {
      // Invalid/tampered room packets never reach the UI.
      return null;
    }
  }
}
