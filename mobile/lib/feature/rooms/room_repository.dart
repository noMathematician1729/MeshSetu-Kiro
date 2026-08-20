import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/database.dart';
import '../../core/model/model.dart';
import 'room_message_packet.dart';
import 'room_policy.dart';
import 'room_presence.dart';

const _uuid = Uuid();

class RoomMessage {
  const RoomMessage({
    required this.eventId,
    required this.text,
    required this.fromPeerId,
    required this.atMs,
    required this.mine,
  });

  final String eventId;
  final String text;
  final String? fromPeerId;
  final int atMs;
  final bool mine;
}

/// `feature/rooms`: composes/reads Room chat, enforcing [RoomPolicy] before
/// a message is allowed onto the durable outbox (Bible §10.2/§10.3 — SOS
/// itself never routes through here, it transcends Room ACL).
class RoomRepository {
  RoomRepository(this._db, {required this.siteId});

  final MeshDatabase _db;
  final String siteId;

  Future<String> sendMessage({
    required RoomPolicy policy,
    required Set<String> userRoles,
    required String text,
  }) async {
    if (!canSend(policy, userRoles)) {
      throw StateError('not authorized to send in ${policy.roomId}');
    }
    final message = text.trim();
    if (message.isEmpty) throw StateError('message must not be empty');
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
            state: const Value('ready'),
            createdAtMs: now,
            updatedAtMs: now,
            expiresAtMs: now + policy.ttlSeconds * 1000,
          ),
        );
    return eventId;
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
