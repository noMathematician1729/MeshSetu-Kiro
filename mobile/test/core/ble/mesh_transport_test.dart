import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble/src/universal_ble.g.dart' show PeripheralService;
import 'package:meshsetu_mobile/core/ble/gatt_peer_session.dart';
import 'package:meshsetu_mobile/core/ble/gatt_server.dart';
import 'package:meshsetu_mobile/core/ble/mesh_gatt.dart';
import 'package:meshsetu_mobile/core/ble/mesh_transport.dart';
import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/core/protocol/frame.dart';
import 'package:meshsetu_mobile/core/protocol/protocol_metrics.dart';
import 'package:meshsetu_mobile/core/protocol/relay_engine.dart';
import 'package:meshsetu_mobile/core/protocol/secure_envelope.dart';

/// Two in-memory [PeerLink]s wired directly to each other, standing in for
/// a real BLE connection between two phones. No radio, no platform channel.
class _FakeLink implements PeerLink {
  _FakeLink({
    this.closeStreamsOnClose = true,
    this.sendSucceeds = true,
    this.throwOnSend = false,
    this.sendGate,
    this.onSend,
    this.mtu = 185,
  });

  final bool closeStreamsOnClose;
  final bool sendSucceeds;
  final bool throwOnSend;
  final Future<void>? sendGate;
  final void Function()? onSend;
  @override
  final int mtu;

  final StreamController<Uint8List> _incomingController =
      StreamController<Uint8List>.broadcast();
  final StreamController<PeerSessionState> _stateController =
      StreamController<PeerSessionState>.broadcast();
  late final _FakeLink peer;
  final List<Uint8List> sentFrames = [];
  bool closed = false;

  bool get hasIncomingListener => _incomingController.hasListener;

  @override
  Stream<Uint8List> get incoming => _incomingController.stream;

  @override
  Stream<PeerSessionState> get state => _stateController.stream;

  @override
  Future<bool> send(Uint8List bytes, {bool withResponse = true}) async {
    sentFrames.add(bytes);
    onSend?.call();
    if (sendGate != null) await sendGate;
    if (throwOnSend) throw StateError('simulated link failure');
    if (!sendSucceeds) return false;
    peer._incomingController.add(bytes);
    return true;
  }

  /// Feed bytes into this link's `incoming` as if the remote peer sent them,
  /// without going through [peer].
  void deliver(Uint8List bytes) => _incomingController.add(bytes);

  void emitState(PeerSessionState state) => _stateController.add(state);

  @override
  Future<void> close() async {
    closed = true;
    if (!closeStreamsOnClose) return;
    await _incomingController.close();
    await _stateController.close();
  }
}

(_FakeLink, _FakeLink) _pairedLinks() {
  final a = _FakeLink();
  final b = _FakeLink();
  a.peer = b;
  b.peer = a;
  return (a, b);
}

class _RecordingStore extends RelayStore {
  final List<MeshEnvelope> stored = [];
  final List<EncryptedObject> deferred = [];

  @override
  void persist(MeshEnvelope envelope, {Uint8List? encryptedBytes}) =>
      stored.add(envelope);

  @override
  void markDeferred(EncryptedObject value) => deferred.add(value);
}

class _FakePeripheral extends UniversalBlePeripheralUnsupported {
  final List<Uint8List> notifications = [];
  int notificationStatus = 0;
  bool emitPreviousNotificationFirst = false;
  int previousNotificationStatus = 1;
  int? maximumNotifyLength;
  int? _lastNotificationId;
  final List<String> reconnectRequests = [];
  OnPeripheralWriteRequest? writeRequestHandler;

  @override
  void setWriteRequestHandler(OnPeripheralWriteRequest? handler) {
    writeRequestHandler = handler;
  }

  @override
  Future<void> addService(
    PeripheralService service, {
    bool primary = true,
    Duration? timeout,
  }) async {
    updateServiceAdded(BlePeripheralServiceAdded(service.uuid, null));
  }

  @override
  Future<void> clearServices() async {}

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) async {
    await _updateCharacteristic(value, deviceId, null);
  }

  @override
  Future<void> updateCharacteristicValueWithId({
    required String characteristicId,
    required Uint8List value,
    required int notificationId,
    String? deviceId,
  }) async {
    await _updateCharacteristic(value, deviceId, notificationId);
  }

  Future<void> _updateCharacteristic(
    Uint8List value,
    String? deviceId,
    int? notificationId,
  ) async {
    if (deviceId != null &&
        emitPreviousNotificationFirst &&
        notifications.isNotEmpty) {
      updateNotificationSent(
        BlePeripheralNotificationSent(
          deviceId,
          previousNotificationStatus,
          _lastNotificationId,
          notifications.last,
        ),
      );
    }
    notifications.add(value);
    _lastNotificationId = notificationId;
    if (deviceId != null) {
      updateNotificationSent(
        BlePeripheralNotificationSent(
          deviceId,
          notificationStatus,
          notificationId,
          value,
        ),
      );
    }
  }

  @override
  Future<void> reconnectPeripheral(String deviceId) async {
    reconnectRequests.add(deviceId);
  }

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) async =>
      maximumNotifyLength;
}

MeshEnvelope _envelope({
  required int objectId,
  required PriorityBand priority,
  required PayloadType payloadType,
  int hopLimit = 0,
  int payloadSize = 3,
}) => MeshEnvelope(
  objectId: objectId,
  eventId: 'event-$objectId',
  siteId: 'site',
  roomId: 'room',
  createdAtMs: 1,
  expiresAtMs: 1000000,
  hopCount: 0,
  hopLimit: hopLimit,
  priority: priority,
  payloadType: payloadType,
  payload: Uint8List.fromList(List<int>.filled(payloadSize, 1)),
  originEphemeralId: 1,
);

MeshTransportCoordinator _coordinator({
  Hello? localHello,
  LossyFrameInterceptor? frameInterceptor,
  MeshGattServer? server,
  RelayStore? store,
  MetricsListener? onMetrics,
}) => MeshTransportCoordinator(
  server: server ?? MeshGattServer(),
  relay: MeshRelayEngine(
    siteId: 'site',
    crypto: AeadEnvelope(List.filled(32, 5)),
    store: store ?? _RecordingStore(),
    clockMs: () => 100,
  ),
  localHello: localHello,
  frameInterceptor: frameInterceptor,
  onMetrics: onMetrics,
);

void main() {
  test('relays an object end-to-end through the pump loop', () async {
    final coordinatorA = _coordinator();
    final coordinatorB = _coordinator();

    final (linkAtoB, linkBtoA) = _pairedLinks();
    coordinatorA.attach('peer-b', linkAtoB, siteFingerprint: 1);
    coordinatorB.attach('peer-a', linkBtoA, siteFingerprint: 2);

    final source = _envelope(
      objectId: 42,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
    );
    final receivedFuture = coordinatorB.incoming.first;
    await coordinatorA.send(source);

    final received = await receivedFuture.timeout(const Duration(seconds: 2));
    expect(received.envelope.objectId, source.objectId);
    expect(received.envelope.eventId, source.eventId);
    expect(received.peerId, 'peer-a');
  });

  test('keeps a queued object until a BLE peer attaches', () async {
    final coordinator = _coordinator();
    final link = _FakeLink()..peer = _FakeLink();
    final source = _envelope(
      objectId: 43,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
    );

    await coordinator.send(source);
    expect(link.sentFrames, isEmpty);

    coordinator.attach('peer-b', link, siteFingerprint: 1);
    // Attaching a READY peer is itself the scheduler wake-up event; a scan
    // tick must not be required to drain a durable object that was already
    // queued.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(link.sentFrames, isNotEmpty);
  });

  test('installs the notification listener before sending HELLO', () async {
    var listenerAtSend = false;
    _FakeLink? link;
    link = _FakeLink(onSend: () => listenerAtSend = link!.hasIncomingListener)
      ..peer = _FakeLink();
    final coordinator = _coordinator(
      localHello: const Hello(
        siteFingerprint: 1,
        ephemeralNodeId: 2,
        capabilities: 1,
        nowEpochSec: 0,
      ),
    );

    coordinator.attach('peer-b', link, siteFingerprint: 1);

    expect(listenerAtSend, isTrue);
  });

  test('SOS priority preempts bulk traffic through the coordinator', () async {
    final coordinatorA = _coordinator();
    final coordinatorB = _coordinator();

    final (linkAtoB, linkBtoA) = _pairedLinks();
    coordinatorA.attach('peer-b', linkAtoB, siteFingerprint: 1);
    coordinatorB.attach('peer-a', linkBtoA, siteFingerprint: 2);

    final bulk = _envelope(
      objectId: 1,
      priority: PriorityBand.p3Bulk,
      payloadType: PayloadType.roomMessage,
    );
    final sos = _envelope(
      objectId: 2,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
    );

    final arrivalOrder = <int>[];
    final done = Completer<void>();
    final subscription = coordinatorB.incoming.listen((received) {
      arrivalOrder.add(received.envelope.objectId);
      if (arrivalOrder.length == 2) done.complete();
    });

    // Enqueue bulk first without draining, so both objects are queued
    // together before a single pump cycle drains them in priority order.
    await coordinatorA.relay.submit(bulk);
    await coordinatorA.send(sos);

    await done.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();

    expect(arrivalOrder, [sos.objectId, bulk.objectId]);
  });

  test(
    'urgent traffic interrupts a fragmented transfer between frames',
    () async {
      final gate = Completer<void>();
      final firstFrameStarted = Completer<void>();
      final coordinator = _coordinator();
      final link = _FakeLink(
        sendGate: gate.future,
        onSend: () {
          if (!firstFrameStarted.isCompleted) firstFrameStarted.complete();
        },
      )..peer = _FakeLink();
      coordinator.attach('peer-b', link, siteFingerprint: 1);

      final bulk = _envelope(
        objectId: 11,
        priority: PriorityBand.p3Bulk,
        payloadType: PayloadType.voiceObject,
        payloadSize: 700,
      );
      final sos = _envelope(
        objectId: 12,
        priority: PriorityBand.p0Critical,
        payloadType: PayloadType.structuredSos,
      );
      await coordinator.relay.submit(bulk);
      final pump = coordinator.tick();
      await firstFrameStarted.future;
      await coordinator.send(sos);
      gate.complete();
      await pump;

      final ids = [
        for (final bytes in link.sentFrames) FrameCodec.decode(bytes).objectId,
      ];
      expect(ids.first, bulk.objectId);
      expect(ids[1], sos.objectId);
    },
  );

  test('replicates to up to maxReplicationPeers attached peers', () async {
    final coordinatorA = _coordinator();
    final linkB = _FakeLink()..peer = _FakeLink();
    final linkC = _FakeLink()..peer = _FakeLink();
    coordinatorA.attach('peer-b', linkB, siteFingerprint: 1);
    coordinatorA.attach('peer-c', linkC, siteFingerprint: 2);

    await coordinatorA.send(
      _envelope(
        objectId: 7,
        priority: PriorityBand.p0Critical,
        payloadType: PayloadType.structuredSos,
      ),
    );
    // Let the pump's async sends settle.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(linkB.sentFrames, isNotEmpty);
    expect(linkC.sentFrames, isNotEmpty);
  });

  test('caps active peer connections independently of replication fan-out', () {
    final coordinator = _coordinator();
    final links = [
      for (var i = 0; i < MeshTransportCoordinator.maxPeerConnections + 1; i++)
        _FakeLink()..peer = _FakeLink(),
    ];
    for (var i = 0; i < links.length; i++) {
      coordinator.attach('peer-$i', links[i], siteFingerprint: 1);
    }

    expect(coordinator.peerCount, MeshTransportCoordinator.maxPeerConnections);
    expect(links.last.closed, isTrue);
  });

  test('dropped debug frames remain queued for a later retry', () async {
    final coordinator = _coordinator(
      frameInterceptor: LossyFrameInterceptor(dropEvery: 1),
    );
    final link = _FakeLink()..peer = _FakeLink();
    coordinator.attach('peer-b', link, siteFingerprint: 1);

    await coordinator.send(
      _envelope(
        objectId: 8,
        priority: PriorityBand.p0Critical,
        payloadType: PayloadType.structuredSos,
      ),
    );

    expect(link.sentFrames, isEmpty);
    expect(coordinator.relay.nextOutbound(), isNotNull);
  });

  test('rejects and closes a peer whose HELLO is for a foreign site', () async {
    final localHello = const Hello(
      siteFingerprint: 111,
      ephemeralNodeId: 1,
      capabilities: 1,
      nowEpochSec: 0,
    );
    final coordinatorA = _coordinator(localHello: localHello);
    final link = _FakeLink()..peer = _FakeLink();
    coordinatorA.attach('peer-b', link, siteFingerprint: 1);

    final foreignHello = const Hello(
      siteFingerprint: 999,
      ephemeralNodeId: 2,
      capabilities: 1,
      nowEpochSec: 0,
    );
    link.deliver(
      FrameCodec.encode(
        MeshFrame(
          type: FrameType.hello,
          priority: 0,
          flags: 0,
          objectId: foreignHello.ephemeralNodeId,
          sequence: 0,
          count: 1,
          payload: HelloCodec.encode(foreignHello),
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(link.closed, isTrue);
    expect(coordinatorA.peerCount, 0);
  });

  test(
    'a stale replacement state event cannot detach the new session',
    () async {
      final coordinator = _coordinator();
      final old = _FakeLink(closeStreamsOnClose: false)..peer = _FakeLink();
      final replacement = _FakeLink()..peer = _FakeLink();

      coordinator.attach('peer-b', old, siteFingerprint: 1);
      coordinator.attach('peer-b', replacement, siteFingerprint: 1);
      old.emitState(PeerSessionState.disconnected);

      await coordinator.send(
        _envelope(
          objectId: 9,
          priority: PriorityBand.p0Critical,
          payloadType: PayloadType.structuredSos,
        ),
      );
      expect(replacement.sentFrames, isNotEmpty);
    },
  );

  test('forwards an object across a three-node relay path', () async {
    final coordinatorA = _coordinator();
    final coordinatorB = _coordinator();
    final coordinatorC = _coordinator();

    final (aToB, bToA) = _pairedLinks();
    final (bToC, cToB) = _pairedLinks();
    coordinatorA.attach('b', aToB, siteFingerprint: 1);
    coordinatorB.attach('a', bToA, siteFingerprint: 1);
    coordinatorB.attach('c', bToC, siteFingerprint: 1);
    coordinatorC.attach('b', cToB, siteFingerprint: 1);

    final received = coordinatorC.incoming.first;
    await coordinatorA.send(
      _envelope(
        objectId: 10,
        priority: PriorityBand.p0Critical,
        payloadType: PayloadType.structuredSos,
        hopLimit: 4,
      ),
    );

    expect(
      (await received.timeout(const Duration(seconds: 2))).envelope.objectId,
      10,
    );
    expect(
      bToA.sentFrames
          .map(FrameCodec.decode)
          .every((frame) => frame.type == FrameType.custodyAck),
      isTrue,
    );
  });

  test('tries later peers when earlier peers are unhealthy', () async {
    final coordinator = _coordinator();
    final failedA = _FakeLink(sendSucceeds: false)..peer = _FakeLink();
    final failedB = _FakeLink(sendSucceeds: false)..peer = _FakeLink();
    final healthy = _FakeLink()..peer = _FakeLink();
    coordinator.attach('a', failedA, siteFingerprint: 1);
    coordinator.attach('b', failedB, siteFingerprint: 1);
    coordinator.attach('c', healthy, siteFingerprint: 1);

    await coordinator.send(
      _envelope(
        objectId: 11,
        priority: PriorityBand.p0Critical,
        payloadType: PayloadType.structuredSos,
      ),
    );

    expect(healthy.sentFrames, isNotEmpty);
  });

  test('send exceptions leave the object queued for retry', () async {
    final coordinator = _coordinator();
    final broken = _FakeLink(throwOnSend: true)..peer = _FakeLink();
    coordinator.attach('broken', broken, siteFingerprint: 1);

    await coordinator.send(
      _envelope(
        objectId: 12,
        priority: PriorityBand.p0Critical,
        payloadType: PayloadType.structuredSos,
      ),
    );

    expect(coordinator.relay.nextOutbound(), isNotNull);
  });

  test('voice deferral waits until every peer rejects its MTU', () async {
    final peripheral = _FakePeripheral();
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );
    final store = _RecordingStore();
    final coordinator = _coordinator(store: store);
    final lowMtu = _FakeLink(mtu: 23)..peer = _FakeLink();
    final usableMtu = _FakeLink(mtu: 185)..peer = _FakeLink();
    coordinator.attach('low-mtu', lowMtu, siteFingerprint: 1);
    coordinator.attach('usable-mtu', usableMtu, siteFingerprint: 1);

    await coordinator.send(
      _envelope(
        objectId: 90,
        priority: PriorityBand.p3Bulk,
        payloadType: PayloadType.voiceObject,
        payloadSize: 3000,
      ),
    );

    expect(lowMtu.sentFrames, isEmpty);
    expect(usableMtu.sentFrames, isNotEmpty);
    expect(store.deferred, isEmpty);
    await coordinator.stop();
  });

  test(
    'voice remains queued when a usable-MTU peer has a send failure',
    () async {
      final peripheral = _FakePeripheral();
      UniversalBlePeripheral.setInstance(peripheral);
      addTearDown(
        () => UniversalBlePeripheral.setInstance(
          UniversalBlePeripheralUnsupported(),
        ),
      );
      final store = _RecordingStore();
      final coordinator = _coordinator(store: store);
      final lowMtu = _FakeLink(mtu: 23)..peer = _FakeLink();
      final failedUsableMtu = _FakeLink(mtu: 185, sendSucceeds: false)
        ..peer = _FakeLink();
      coordinator.attach('low-mtu', lowMtu, siteFingerprint: 1);
      coordinator.attach(
        'failed-usable-mtu',
        failedUsableMtu,
        siteFingerprint: 1,
      );

      await coordinator.send(
        _envelope(
          objectId: 91,
          priority: PriorityBand.p3Bulk,
          payloadType: PayloadType.voiceObject,
          payloadSize: 3000,
        ),
      );

      expect(store.deferred, isEmpty);
      expect(coordinator.relay.nextOutbound(), isNotNull);
      await coordinator.stop();
    },
  );

  test('each peer-state listener receives the current snapshot', () async {
    final coordinator = _coordinator();
    final link = _FakeLink()..peer = _FakeLink();
    coordinator.attach('peer', link, siteFingerprint: 1);

    expect((await coordinator.peerState.first).single.peerId, 'peer');
    expect((await coordinator.peerState.first).single.peerId, 'peer');
  });

  test(
    'a still-subscribed capacity peer can be admitted after a slot opens',
    () async {
      final peripheral = _FakePeripheral();
      UniversalBlePeripheral.setInstance(peripheral);
      final previousTarget = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previousTarget;
        UniversalBlePeripheral.setInstance(UniversalBlePeripheralUnsupported());
      });

      final server = MeshGattServer();
      await server.start();
      peripheral.updateMtu(BlePeripheralMtuChanged('peer', 185));
      await Future<void>.delayed(Duration.zero);
      expect(await server.mtuFor('peer'), 185);
      peripheral.maximumNotifyLength = 30;
      peripheral.updateConnectionState(
        BlePeripheralConnectionStateChanged('peer', false),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await server.mtuFor('peer'), 33);
      peripheral.updateConnectionState(
        BlePeripheralConnectionStateChanged('peer', true),
      );
      peripheral.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'peer',
          characteristicId: MeshGatt.tx,
          isSubscribed: true,
          name: null,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      server.rejectPeer('peer');
      expect(
        await server.notifyAwait('peer', Uint8List.fromList([1])),
        isFalse,
      );
      expect(server.admitPeer('peer'), isTrue);
      expect(await server.notifyAwait('peer', Uint8List.fromList([1])), isTrue);
      expect(peripheral.notifications, hasLength(1));
      peripheral.emitPreviousNotificationFirst = true;
      // The stale callback intentionally carries the same payload as the
      // current send; only its notification id makes it unambiguous.
      expect(await server.notifyAwait('peer', Uint8List.fromList([2])), isTrue);
      expect(await server.notifyAwait('peer', Uint8List.fromList([2])), isTrue);
      peripheral.notificationStatus = 1;
      expect(
        await server.notifyAwait('peer', Uint8List.fromList([3])),
        isFalse,
      );
      await server.stop();
    },
  );

  test(
    'a physically disconnected capacity peer stays pending until it resubscribes',
    () async {
      final peripheral = _FakePeripheral();
      UniversalBlePeripheral.setInstance(peripheral);
      addTearDown(
        () => UniversalBlePeripheral.setInstance(
          UniversalBlePeripheralUnsupported(),
        ),
      );

      final server = MeshGattServer();
      await server.start();
      peripheral.updateConnectionState(
        BlePeripheralConnectionStateChanged('peer', true),
      );
      peripheral.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'peer',
          characteristicId: MeshGatt.tx,
          isSubscribed: true,
          name: null,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      server.rejectPeer('peer');

      peripheral.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'peer',
          characteristicId: MeshGatt.tx,
          isSubscribed: false,
          name: null,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(server.isPeerRejected('peer'), isTrue);
      expect(server.hasLiveSubscription('peer'), isFalse);

      await server.reconnectPeer('peer');
      expect(peripheral.reconnectRequests, ['peer']);

      peripheral.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'peer',
          characteristicId: MeshGatt.tx,
          isSubscribed: true,
          name: null,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(server.isPeerRejected('peer'), isFalse);
      expect(server.hasLiveSubscription('peer'), isTrue);
      await server.stop();
    },
  );

  test(
    'reconnects a rejected peer when its subscription survives disconnect',
    () async {
      final peripheral = _FakePeripheral();
      UniversalBlePeripheral.setInstance(peripheral);
      addTearDown(
        () => UniversalBlePeripheral.setInstance(
          UniversalBlePeripheralUnsupported(),
        ),
      );

      final server = MeshGattServer();
      await server.start();
      peripheral.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'peer',
          characteristicId: MeshGatt.tx,
          isSubscribed: true,
          name: null,
        ),
      );
      peripheral.updateConnectionState(
        BlePeripheralConnectionStateChanged('peer', true),
      );
      await Future<void>.delayed(Duration.zero);

      server.rejectPeer('peer');
      peripheral.updateConnectionState(
        BlePeripheralConnectionStateChanged('peer', false),
      );
      await Future<void>.delayed(Duration.zero);
      expect(server.hasLiveSubscription('peer'), isFalse);

      await server.reconnectPeer('peer');
      expect(peripheral.reconnectRequests, ['peer']);
      peripheral.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'peer',
          characteristicId: MeshGatt.tx,
          isSubscribed: true,
          name: null,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(server.isPeerRejected('peer'), isFalse);
      await server.stop();
    },
  );

  test('transport promotes a rejected server peer when a slot opens', () async {
    final peripheral = _FakePeripheral();
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );

    final server = MeshGattServer();
    final coordinator = _coordinator(server: server);
    await coordinator.start();
    final links = [
      for (var i = 0; i < MeshTransportCoordinator.maxPeerConnections; i++)
        _FakeLink()..peer = _FakeLink(),
    ];
    for (var i = 0; i < links.length; i++) {
      coordinator.attach('central-$i', links[i], siteFingerprint: 1);
    }

    for (final peerId in ['server-peer-a', 'server-peer-b']) {
      peripheral.updateConnectionState(
        BlePeripheralConnectionStateChanged(peerId, true),
      );
      peripheral.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: peerId,
          characteristicId: MeshGatt.tx,
          isSubscribed: true,
          name: null,
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(coordinator.hasPeer('server-peer-a'), isFalse);
    expect(coordinator.hasPeer('server-peer-b'), isFalse);

    for (final peerId in ['server-peer-a', 'server-peer-b']) {
      peripheral.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: peerId,
          characteristicId: MeshGatt.tx,
          isSubscribed: false,
          name: null,
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);

    links.first.emitState(PeerSessionState.disconnected);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(peripheral.reconnectRequests, ['server-peer-a', 'server-peer-b']);

    peripheral.updateCharacteristicSubscription(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: 'server-peer-a',
        characteristicId: MeshGatt.tx,
        isSubscribed: true,
        name: null,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(coordinator.hasPeer('server-peer-a'), isTrue);
    expect(coordinator.hasPeer('server-peer-b'), isFalse);
    await coordinator.stop();
  });

  test('server unsubscribe detaches its transport session', () async {
    final peripheral = _FakePeripheral();
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );

    final server = MeshGattServer();
    final coordinator = _coordinator(server: server);
    await coordinator.start();
    peripheral.updateConnectionState(
      BlePeripheralConnectionStateChanged('server-peer', true),
    );
    peripheral.updateCharacteristicSubscription(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: 'server-peer',
        characteristicId: MeshGatt.tx,
        isSubscribed: true,
        name: null,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(coordinator.hasPeer('server-peer'), isTrue);

    peripheral.updateCharacteristicSubscription(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: 'server-peer',
        characteristicId: MeshGatt.tx,
        isSubscribed: false,
        name: null,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(coordinator.hasPeer('server-peer'), isFalse);
    await coordinator.stop();
  });

  test('foreign server HELLO remains quarantined after detaching', () async {
    final peripheral = _FakePeripheral();
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );
    final server = MeshGattServer();
    final coordinator = _coordinator(
      server: server,
      localHello: const Hello(
        siteFingerprint: 111,
        ephemeralNodeId: 1,
        capabilities: 1,
        nowEpochSec: 0,
      ),
    );
    await coordinator.start();
    peripheral.updateConnectionState(
      BlePeripheralConnectionStateChanged('foreign-peer', true),
    );
    peripheral.updateCharacteristicSubscription(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: 'foreign-peer',
        characteristicId: MeshGatt.tx,
        isSubscribed: true,
        name: null,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final foreignHello = const Hello(
      siteFingerprint: 999,
      ephemeralNodeId: 2,
      capabilities: 1,
      nowEpochSec: 0,
    );
    final result = peripheral.writeRequestHandler?.call(
      'foreign-peer',
      MeshGatt.rx,
      0,
      FrameCodec.encode(
        MeshFrame(
          type: FrameType.hello,
          priority: 0,
          flags: 0,
          objectId: foreignHello.ephemeralNodeId,
          sequence: 0,
          count: 1,
          payload: HelloCodec.encode(foreignHello),
        ),
      ),
    );
    expect(result, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(coordinator.peerCount, 0);
    expect(server.isPeerRejected('foreign-peer'), isTrue);
    await coordinator.stop();
  });

  test(
    'server RX callback accepts a MeshSetu frame after subscription',
    () async {
      final peripheral = _FakePeripheral();
      UniversalBlePeripheral.setInstance(peripheral);
      addTearDown(
        () => UniversalBlePeripheral.setInstance(
          UniversalBlePeripheralUnsupported(),
        ),
      );
      final metrics = <RelayMetric>[];
      final server = MeshGattServer();
      final coordinator = _coordinator(
        server: server,
        onMetrics: metrics.addAll,
      );
      await coordinator.start();
      peripheral.updateConnectionState(
        BlePeripheralConnectionStateChanged('client', true),
      );
      peripheral.updateCharacteristicSubscription(
        BlePeripheralCharacteristicSubscriptionChanged(
          deviceId: 'client',
          characteristicId: MeshGatt.tx,
          isSubscribed: true,
          name: null,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final result = peripheral.writeRequestHandler?.call(
        'client',
        MeshGatt.rx,
        0,
        FrameCodec.encode(
          MeshFrame(
            type: FrameType.hello,
            priority: 0,
            flags: 0,
            objectId: 7,
            sequence: 0,
            count: 1,
            payload: HelloCodec.encode(
              const Hello(
                siteFingerprint: 1,
                ephemeralNodeId: 7,
                capabilities: 1,
                nowEpochSec: 0,
              ),
            ),
          ),
        ),
      );
      expect(result, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(metrics.any((metric) => metric.kind == 'frame_rx'), isTrue);
      await coordinator.stop();
    },
  );
}
