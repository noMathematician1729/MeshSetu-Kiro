import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/gatt_peer_session.dart';
import 'package:meshsetu_mobile/core/ble/gatt_server.dart';
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
  });

  final bool closeStreamsOnClose;
  final bool sendSucceeds;
  final bool throwOnSend;
  @override
  final int mtu = 185;

  final StreamController<Uint8List> _incomingController =
      StreamController<Uint8List>.broadcast();
  final StreamController<PeerSessionState> _stateController =
      StreamController<PeerSessionState>.broadcast();
  late final _FakeLink peer;
  final List<Uint8List> sentFrames = [];
  bool closed = false;

  @override
  Stream<Uint8List> get incoming => _incomingController.stream;

  @override
  Stream<PeerSessionState> get state => _stateController.stream;

  @override
  Future<bool> send(Uint8List bytes, {bool withResponse = true}) async {
    sentFrames.add(bytes);
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

  @override
  void persist(MeshEnvelope envelope) => stored.add(envelope);
}

MeshEnvelope _envelope({
  required int objectId,
  required PriorityBand priority,
  required PayloadType payloadType,
  int hopLimit = 0,
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
  payload: Uint8List.fromList([1, 2, 3]),
  originEphemeralId: 1,
);

MeshTransportCoordinator _coordinator({
  Hello? localHello,
  LossyFrameInterceptor? frameInterceptor,
}) => MeshTransportCoordinator(
  server: MeshGattServer(),
  relay: MeshRelayEngine(
    siteId: 'site',
    crypto: AeadEnvelope(List.filled(32, 5)),
    store: _RecordingStore(),
    clockMs: () => 100,
  ),
  localHello: localHello,
  frameInterceptor: frameInterceptor,
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

  test('each peer-state listener receives the current snapshot', () async {
    final coordinator = _coordinator();
    final link = _FakeLink()..peer = _FakeLink();
    coordinator.attach('peer', link, siteFingerprint: 1);

    expect((await coordinator.peerState.first).single.peerId, 'peer');
    expect((await coordinator.peerState.first).single.peerId, 'peer');
  });
}
