import 'dart:async';

import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:meshsetu_mobile/core/ble/gatt_peer_session.dart';
import 'package:meshsetu_mobile/core/ble/gatt_server.dart';
import 'package:meshsetu_mobile/core/ble/mesh_transport.dart';
import 'package:meshsetu_mobile/core/data/database.dart';
import 'package:meshsetu_mobile/core/data/outbox_sender.dart';
import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/core/protocol/relay_engine.dart';
import 'package:meshsetu_mobile/core/protocol/secure_envelope.dart';
import 'package:meshsetu_mobile/feature/rooms/room_message_dispatcher.dart';
import 'package:meshsetu_mobile/feature/rooms/room_message_packet.dart';
import 'package:meshsetu_mobile/feature/rooms/room_policy.dart';
import 'package:meshsetu_mobile/feature/rooms/room_presence_socket.dart';
import 'package:meshsetu_mobile/feature/rooms/room_repository.dart';
import 'package:test/test.dart';
import 'package:universal_ble/universal_ble.dart';

class _FakeLiveTransport implements LiveRoomMessageTransport {
  _FakeLiveTransport({required this.canReachOtherMember, required this.result});

  @override
  final bool canReachOtherMember;
  final bool result;
  final sent = <({String messageId, String text})>[];

  @override
  Future<bool> sendRoomMessage({
    required String messageId,
    required String text,
  }) async {
    sent.add((messageId: messageId, text: text));
    return result;
  }
}

class _MemoryRelayStore extends RelayStore {
  @override
  void persist(MeshEnvelope envelope, {Uint8List? encryptedBytes}) {}
}

class _NoopPeripheral extends UniversalBlePeripheralUnsupported {
  @override
  Future<void> clearServices() async {}
}

class _PairedMeshLink implements PeerLink {
  final _incoming = StreamController<Uint8List>.broadcast();
  final _state = StreamController<PeerSessionState>.broadcast();
  late final _PairedMeshLink peer;

  @override
  int get mtu => 185;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<PeerSessionState> get state => _state.stream;

  @override
  Future<bool> send(Uint8List bytes, {bool withResponse = true}) async {
    peer._incoming.add(bytes);
    return true;
  }

  @override
  Future<void> close() async {
    await _incoming.close();
    await _state.close();
  }
}

MeshTransportCoordinator _meshCoordinator() => MeshTransportCoordinator(
  server: MeshGattServer(),
  relay: MeshRelayEngine(
    siteId: 'site',
    crypto: AeadEnvelope(List<int>.filled(32, 7)),
    store: _MemoryRelayStore(),
    clockMs: () => DateTime.now().millisecondsSinceEpoch,
  ),
);

void main() {
  late MeshDatabase db;
  late RoomRepository repository;

  setUp(() {
    db = MeshDatabase.forTesting(NativeDatabase.memory());
    repository = RoomRepository(db, siteId: 'site');
  });

  tearDown(() => db.close());

  test('uses only the socket when another internet peer accepts', () async {
    final live = _FakeLiveTransport(canReachOtherMember: true, result: true);

    final delivery = await RoomMessageDispatcher(repository, live).send(
      policy: policyForRole('public', 'public'),
      userRoles: const {'public'},
      text: ' hello ',
    );

    final row = await (db.select(
      db.outboxEvents,
    )..where((row) => row.eventId.equals(delivery.eventId))).getSingle();
    expect(delivery.route, RoomMessageRoute.socket);
    expect(row.state, 'acked');
    expect(live.sent.single.text, 'hello');
  });

  test('queues directly for GATT when no internet peer exists', () async {
    final live = _FakeLiveTransport(canReachOtherMember: false, result: true);

    final delivery = await RoomMessageDispatcher(repository, live).send(
      policy: policyForRole('public', 'public'),
      userRoles: const {'public'},
      text: 'offline',
    );

    final row = await (db.select(
      db.outboxEvents,
    )..where((row) => row.eventId.equals(delivery.eventId))).getSingle();
    expect(delivery.route, RoomMessageRoute.gatt);
    expect(row.state, RoomRepository.meshReadyState);
    expect(live.sent, isEmpty);
  });

  test('promotes a failed socket delivery to the GATT outbox', () async {
    final live = _FakeLiveTransport(canReachOtherMember: true, result: false);

    final delivery = await RoomMessageDispatcher(repository, live).send(
      policy: policyForRole('public', 'public'),
      userRoles: const {'public'},
      text: 'fallback',
    );

    final row = await (db.select(
      db.outboxEvents,
    )..where((row) => row.eventId.equals(delivery.eventId))).getSingle();
    expect(delivery.route, RoomMessageRoute.gatt);
    expect(row.state, RoomRepository.meshReadyState);
    expect(live.sent, hasLength(1));
  });

  test('offline delivery drains as a room envelope into the mesh', () async {
    final submitted = Completer<MeshEnvelope>();
    final sender = OutboxSender(
      db,
      (envelope) async => submitted.complete(envelope),
      siteId: 'site',
      localEphemeralId: 7,
    )..start();
    addTearDown(sender.dispose);

    final delivery = await RoomMessageDispatcher(repository).send(
      policy: policyForRole('public', 'public'),
      userRoles: const {'public'},
      text: 'through gatt',
    );
    final envelope = await submitted.future.timeout(const Duration(seconds: 1));

    expect(delivery.route, RoomMessageRoute.gatt);
    expect(envelope.payloadType, PayloadType.roomMessage);
    expect(envelope.eventId, delivery.eventId);
    expect(
      RoomMessagePacketCodec.decode(
        siteId: envelope.siteId,
        roomId: envelope.roomId,
        eventId: envelope.eventId,
        packet: envelope.payload,
      ),
      'through gatt',
    );
  });

  test('offline room message reaches a second repository over mesh', () async {
    final previousDatabaseWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    UniversalBlePeripheral.setInstance(_NoopPeripheral());
    final receiverDb = MeshDatabase.forTesting(NativeDatabase.memory());
    final receiverRepository = RoomRepository(receiverDb, siteId: 'site');
    final senderMesh = _meshCoordinator();
    final receiverMesh = _meshCoordinator();
    final senderLink = _PairedMeshLink();
    final receiverLink = _PairedMeshLink();
    senderLink.peer = receiverLink;
    receiverLink.peer = senderLink;
    senderMesh.attach('receiver', senderLink, siteFingerprint: 1);
    receiverMesh.attach('sender', receiverLink, siteFingerprint: 1);

    final incomingSubscription = receiverMesh.incoming.listen((received) {
      final envelope = received.envelope;
      unawaited(
        receiverDb.insertInbox(
          InboxEventsCompanion.insert(
            objectId: Value(envelope.objectId),
            eventId: envelope.eventId,
            siteId: envelope.siteId,
            roomId: envelope.roomId,
            payloadType: envelope.payloadType.name,
            payload: envelope.payload,
            peerId: received.peerId,
            receivedAtMs: received.receivedAtMs,
          ),
        ),
      );
    });
    final sender = OutboxSender(
      db,
      (envelope) async => senderMesh.send(envelope),
      siteId: 'site',
      localEphemeralId: 7,
    )..start();
    addTearDown(() async {
      await sender.dispose();
      await incomingSubscription.cancel();
      await senderMesh.stop();
      await receiverMesh.stop();
      await receiverDb.close();
      UniversalBlePeripheral.setInstance(UniversalBlePeripheralUnsupported());
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousDatabaseWarningSetting;
    });

    final receivedMessage = receiverRepository
        .watch(
          policy: policyForRole('public', 'public'),
          userRoles: const {'public'},
        )
        .firstWhere((messages) => messages.isNotEmpty);
    final delivery = await RoomMessageDispatcher(repository).send(
      policy: policyForRole('public', 'public'),
      userRoles: const {'public'},
      text: 'radio path',
    );

    final messages = await receivedMessage.timeout(const Duration(seconds: 2));
    expect(delivery.route, RoomMessageRoute.gatt);
    expect(messages.single.eventId, delivery.eventId);
    expect(messages.single.text, 'radio path');
    expect(messages.single.mine, isFalse);
  });

  test('socket receive is durable and duplicate deliveries converge', () async {
    for (var i = 0; i < 2; i++) {
      await repository.storeSocketMessage(
        roomId: 'public',
        eventId: 'remote-event',
        text: 'persistent',
        fromPeerId: 'Remote user',
        sentAtMs: 42,
      );
    }

    final rows = await db.select(db.inboxEvents).get();
    final messages = await repository
        .watch(
          policy: policyForRole('public', 'public'),
          userRoles: const {'public'},
        )
        .first;

    expect(rows, hasLength(1));
    expect(messages.single.eventId, 'remote-event');
    expect(messages.single.text, 'persistent');
    expect(messages.single.fromPeerId, 'Remote user');
  });
}
