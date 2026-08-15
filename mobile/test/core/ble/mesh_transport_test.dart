import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/gatt_server.dart';
import 'package:meshsetu_mobile/core/ble/mesh_transport.dart';
import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/core/protocol/relay_engine.dart';
import 'package:meshsetu_mobile/core/protocol/secure_envelope.dart';

/// Two in-memory [PeerLink]s wired directly to each other, standing in for
/// a real BLE connection between two phones. No radio, no platform channel.
class _FakeLink implements PeerLink {
  @override
  final int mtu = 185;

  final StreamController<Uint8List> _incomingController =
      StreamController<Uint8List>.broadcast();
  late final _FakeLink peer;

  @override
  Stream<Uint8List> get incoming => _incomingController.stream;

  @override
  Future<bool> send(Uint8List bytes, {bool withResponse = true}) async {
    peer._incomingController.add(bytes);
    return true;
  }
}

(PeerLink, PeerLink) _pairedLinks() {
  final a = _FakeLink();
  final b = _FakeLink();
  a.peer = b;
  b.peer = a;
  return (a, b);
}

class _RecordingStore implements RelayStore {
  final List<MeshEnvelope> stored = [];

  @override
  void persist(MeshEnvelope envelope) => stored.add(envelope);
}

MeshEnvelope _envelope({
  required int objectId,
  required PriorityBand priority,
  required PayloadType payloadType,
}) => MeshEnvelope(
  objectId: objectId,
  eventId: 'event-$objectId',
  siteId: 'site',
  roomId: 'room',
  createdAtMs: 1,
  expiresAtMs: 1000000,
  hopCount: 0,
  hopLimit: 0,
  priority: priority,
  payloadType: payloadType,
  payload: Uint8List.fromList([1, 2, 3]),
  originEphemeralId: 1,
);

void main() {
  test('relays an object end-to-end through the pump loop', () async {
    final key = List.filled(32, 5);
    final coordinatorA = MeshTransportCoordinator(
      server: MeshGattServer(),
      relay: MeshRelayEngine(
        siteId: 'site',
        crypto: AeadEnvelope(key),
        store: _RecordingStore(),
        clockMs: () => 100,
      ),
    );
    final coordinatorB = MeshTransportCoordinator(
      server: MeshGattServer(),
      relay: MeshRelayEngine(
        siteId: 'site',
        crypto: AeadEnvelope(key),
        store: _RecordingStore(),
        clockMs: () => 100,
      ),
    );

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
    final key = List.filled(32, 6);
    final coordinatorA = MeshTransportCoordinator(
      server: MeshGattServer(),
      relay: MeshRelayEngine(
        siteId: 'site',
        crypto: AeadEnvelope(key),
        store: _RecordingStore(),
        clockMs: () => 100,
      ),
    );
    final coordinatorB = MeshTransportCoordinator(
      server: MeshGattServer(),
      relay: MeshRelayEngine(
        siteId: 'site',
        crypto: AeadEnvelope(key),
        store: _RecordingStore(),
        clockMs: () => 100,
      ),
    );

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
}
