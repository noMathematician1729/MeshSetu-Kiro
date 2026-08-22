import 'dart:convert';

import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:meshsetu_mobile/core/data/database.dart';
import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/feature/rooms/room_policy.dart';
import 'package:meshsetu_mobile/feature/rooms/room_presence.dart';
import 'package:meshsetu_mobile/feature/rooms/room_repository.dart';

const _policy = RoomPolicy(
  roomId: 'public',
  sendRoles: {'public'},
  readRoles: {'public'},
  trafficClass: TrafficClass.roomMessage,
  ttlSeconds: 60,
);

void main() {
  late MeshDatabase db;
  late RoomRepository repository;

  setUp(() {
    db = MeshDatabase.forTesting(NativeDatabase.memory());
    repository = RoomRepository(db, siteId: 'site');
  });

  tearDown(() => db.close());

  test('enforces the 512-byte mesh room-message budget by UTF-8 byte count',
      () async {
    final exactly512Utf8Bytes = List<String>.filled(256, 'é').join();
    final eventId = await repository.sendMessage(
      policy: _policy,
      userRoles: const {'public'},
      text: exactly512Utf8Bytes,
    );
    final row = await (db.select(
      db.outboxEvents,
    )..where((event) => event.eventId.equals(eventId))).getSingle();
    expect(utf8.encode(row.rawText!).length, 512);
    expect(row.state, RoomRepository.meshReadyState);

    await expectLater(
      repository.sendMessage(
        policy: _policy,
        userRoles: const {'public'},
        text: '$exactly512Utf8Bytes\u00e9',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('514 bytes'),
        ),
      ),
    );
    expect(await db.select(db.outboxEvents).get(), hasLength(1));
  });

  test('maps durable outbox states to room delivery states', () async {
    final queued = await repository.sendMessage(
      policy: _policy,
      userRoles: const {'public'},
      text: 'queued',
    );
    final sending = await repository.sendMessage(
      policy: _policy,
      userRoles: const {'public'},
      text: 'sending',
      initialState: RoomRepository.socketPendingState,
    );
    final delivered = await repository.sendMessage(
      policy: _policy,
      userRoles: const {'public'},
      text: 'delivered',
    );
    final failed = await repository.sendMessage(
      policy: _policy,
      userRoles: const {'public'},
      text: 'failed',
    );
    await repository.markSocketDelivered(delivered);
    await db.markState(failed, 'failed', DateTime.now().millisecondsSinceEpoch);

    final messages = await repository
        .watch(policy: _policy, userRoles: const {'public'})
        .firstWhere((items) => items.length == 4);
    final byEventId = {for (final message in messages) message.eventId: message};

    expect(byEventId[queued]!.state, RoomMessageState.queued);
    expect(byEventId[sending]!.state, RoomMessageState.sending);
    expect(byEventId[delivered]!.state, RoomMessageState.delivered);
    expect(byEventId[failed]!.state, RoomMessageState.failed);
  });

  test('received socket message is durable, delivered, and deduplicated',
      () async {
    for (var i = 0; i < 2; i++) {
      await repository.storeSocketMessage(
        roomId: _policy.roomId,
        eventId: 'remote-message-1',
        text: 'offline peer message',
        fromPeerId: 'Remote',
        sentAtMs: 42,
      );
    }

    final messages = await repository
        .watch(policy: _policy, userRoles: const {'public'})
        .firstWhere((items) => items.length == 1);

    expect(messages.single.mine, isFalse);
    expect(messages.single.text, 'offline peer message');
    expect(messages.single.fromPeerId, 'Remote');
    expect(messages.single.state, RoomMessageState.delivered);
    expect(await db.select(db.inboxEvents).get(), hasLength(1));
  });

  test('room entry presence announcement is a ready mesh envelope', () async {
    await repository.announceMember(
      roomId: _policy.roomId,
      memberId: 'profile-1',
      displayName: 'Asha',
    );

    final row = (await db.select(db.outboxEvents).get()).single;
    expect(row.payloadType, PayloadType.responderUpdate.name);
    expect(row.state, RoomRepository.meshReadyState);
    final member = RoomPresenceCodec.decode(row.payload!);
    expect(member?.memberId, 'profile-1');
    expect(member?.displayName, 'Asha');
  });

  test('room presence refuses incomplete member identity', () async {
    await expectLater(
      repository.announceMember(
        roomId: '',
        memberId: 'profile-1',
        displayName: 'Asha',
      ),
      throwsArgumentError,
    );
  });

  group('queuedReasonFor', () {
    RoomMessage queuedMessage({int? queuedSinceMs}) => RoomMessage(
      eventId: 'e1',
      text: 'hi',
      fromPeerId: null,
      atMs: 0,
      mine: true,
      state: RoomMessageState.queued,
      queuedSinceMs: queuedSinceMs,
    );

    test('returns null before the stall threshold has elapsed', () {
      final reason = queuedReasonFor(
        queuedMessage(queuedSinceMs: 1000),
        eventModeRunning: true,
        peerCount: 0,
        blockedReason: null,
        siteMismatchDetected: false,
        nowMs: 1000 + const Duration(seconds: 5).inMilliseconds,
      );
      expect(reason, isNull);
    });

    test('returns null for a delivered message regardless of elapsed time', () {
      final reason = queuedReasonFor(
        RoomMessage(
          eventId: 'e1',
          text: 'hi',
          fromPeerId: null,
          atMs: 0,
          mine: true,
          state: RoomMessageState.delivered,
        ),
        eventModeRunning: true,
        peerCount: 0,
        blockedReason: null,
        siteMismatchDetected: false,
        nowMs: 1000000,
      );
      expect(reason, isNull);
    });

    test('surfaces the blocked-radio reason once stalled and event mode is off', () {
      final reason = queuedReasonFor(
        queuedMessage(queuedSinceMs: 0),
        eventModeRunning: false,
        peerCount: 0,
        blockedReason: 'Turn on Location in Settings.',
        siteMismatchDetected: false,
        nowMs: const Duration(seconds: 25).inMilliseconds,
      );
      expect(reason, 'Turn on Location in Settings.');
    });

    test('reports waiting for a nearby device when running with no peers', () {
      final reason = queuedReasonFor(
        queuedMessage(queuedSinceMs: 0),
        eventModeRunning: true,
        peerCount: 0,
        blockedReason: null,
        siteMismatchDetected: false,
        nowMs: const Duration(seconds: 25).inMilliseconds,
      );
      expect(reason, contains('nearby device'));
    });

    test('reports a site mismatch when peers are seen but on a different site', () {
      final reason = queuedReasonFor(
        queuedMessage(queuedSinceMs: 0),
        eventModeRunning: true,
        peerCount: 0,
        blockedReason: null,
        siteMismatchDetected: true,
        nowMs: const Duration(seconds: 25).inMilliseconds,
      );
      expect(reason, contains('different event/site'));
    });

    test('reports relaying once a peer is connected', () {
      final reason = queuedReasonFor(
        queuedMessage(queuedSinceMs: 0),
        eventModeRunning: true,
        peerCount: 1,
        blockedReason: null,
        siteMismatchDetected: false,
        nowMs: const Duration(seconds: 25).inMilliseconds,
      );
      expect(reason, contains('relay'));
    });
  });
}
