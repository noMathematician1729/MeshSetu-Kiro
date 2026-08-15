import 'dart:async';
import 'dart:typed_data';

import '../model/model.dart';
import '../protocol/frame.dart';
import '../protocol/relay_engine.dart';
import 'gatt_peer_session.dart';
import 'gatt_server.dart';

class SendTicket {
  const SendTicket(this.objectId);
  final int objectId;
}

abstract interface class MeshTransport {
  Stream<ReceivedObject> get incoming;
  Stream<List<PeerState>> get peerState;
  Future<SendTicket> send(MeshEnvelope value);
}

/// Narrow interface over [GattPeerSession] that [MeshTransportCoordinator]
/// depends on, instead of the concrete session class. This is the one piece
/// of this port that isn't in the Kotlin source: it exists purely so the
/// pump/priority/relay orchestration logic below can be exercised in tests
/// against a fake in-memory link, without a real BLE radio.
abstract interface class PeerLink {
  int get mtu;
  Stream<Uint8List> get incoming;
  Future<bool> send(Uint8List bytes, {bool withResponse = true});
}

/// Adapts a real [GattPeerSession] to [PeerLink], turning Kotlin's
/// `Result<Unit>`-returning `send` into a plain success/failure `bool`
/// (matching how the Kotlin pump loop already only cared about
/// `.isSuccess`).
class GattPeerSessionLink implements PeerLink {
  GattPeerSessionLink(this._session);
  final GattPeerSession _session;

  @override
  int get mtu => _session.mtu;

  @override
  Stream<Uint8List> get incoming => _session.incoming;

  @override
  Future<bool> send(Uint8List bytes, {bool withResponse = true}) async {
    try {
      await _session.send(bytes, withResponse: withResponse);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// A minimal async mutex, standing in for Kotlin's `kotlinx.coroutines.sync.Mutex`.
/// Dart has no stdlib/pub equivalent worth adding a dependency for; this is
/// the whole implementation — queue continuations behind the previous one.
class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        release.complete();
      }
    });
  }
}

/// Port of `in.meshsetu.ble.MeshTransportCoordinator` (Kotlin
/// `MeshTransport.kt`).
///
/// Deviations from the Kotlin source:
/// - No `CoroutineScope` parameter — Dart `Stream.listen` callbacks already
///   run on the event loop; there's no separate dispatcher to launch onto.
/// - Depends on [PeerLink] instead of [GattPeerSession] directly (see above).
/// - The pump loop's "send to `sessions.entries.first`" behavior — i.e. it
///   only ever targets the first attached peer, not a real multi-peer
///   fan-out — is preserved exactly as-is from the Kotlin source. This is
///   existing behavior being ported, not a new design decision.
class MeshTransportCoordinator implements MeshTransport {
  MeshTransportCoordinator({required this.server, required this.relay}) {
    relay.addPersistListener((envelope, peerId) {
      _receivedController.add(
        ReceivedObject(
          envelope: envelope,
          peerId: peerId,
          receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  final MeshGattServer server;
  final MeshRelayEngine relay;

  final StreamController<ReceivedObject> _receivedController =
      StreamController<ReceivedObject>.broadcast();
  final StreamController<List<PeerState>> _peersController =
      StreamController<List<PeerState>>.broadcast();
  List<PeerState> _peers = [];

  final Map<String, PeerLink> _sessions = {};
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final _AsyncLock _pumpLock = _AsyncLock();

  @override
  Stream<ReceivedObject> get incoming => _receivedController.stream;

  @override
  Stream<List<PeerState>> get peerState => _peersController.stream;

  Future<void> start() async {
    await server.start();
    _subscriptions.add(
      server.incoming.listen((frame) async {
        final result = await relay.receive(frame.deviceId, frame.bytes);
        for (final controlFrame in result.controlFrames) {
          await server.notify(frame.deviceId, controlFrame);
        }
        await _pump();
      }),
    );
  }

  void attach(
    String peerId,
    PeerLink link, {
    required int siteFingerprint,
    int? rssi,
  }) {
    _sessions[peerId] = link;
    _peers = [
      for (final p in _peers)
        if (p.peerId != peerId) p,
      PeerState(
        peerId: peerId,
        siteFingerprint: siteFingerprint,
        connected: true,
        mtu: link.mtu,
        rssi: rssi,
        queuedObjects: 0,
        lastSeenMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    _peersController.add(_peers);
    _subscriptions.add(
      link.incoming.listen((bytes) async {
        final result = await relay.receive(peerId, bytes);
        for (final controlFrame in result.controlFrames) {
          await link.send(controlFrame, withResponse: true);
        }
        await _pump();
      }),
    );
  }

  @override
  Future<SendTicket> send(MeshEnvelope value) async {
    await relay.submit(value);
    await _pump();
    return SendTicket(value.objectId);
  }

  Future<void> _pump() => _pumpLock.synchronized(() async {
    if (_sessions.isEmpty) return;
    while (true) {
      final objectToSend = relay.nextOutbound();
      if (objectToSend == null) return;
      if (_sessions.isEmpty) return;
      final link = _sessions.values.first;
      var sent = true;
      try {
        final frames = fragment(
          objectId: objectToSend.objectId,
          priority: objectToSend.trafficClass.rank,
          encrypted: objectToSend.bytes,
          mtu: link.mtu,
        );
        for (final frame in frames) {
          final ok = await link.send(
            FrameCodec.encode(frame),
            withResponse: objectToSend.trafficClass.rank <= 2,
          );
          if (!ok) {
            sent = false;
            break;
          }
        }
      } catch (_) {
        sent = false;
      }
      if (!sent) {
        relay.requeue(objectToSend);
        return;
      }
    }
  });

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _sessions.clear();
    await server.stop();
    _peers = [];
    _peersController.add(_peers);
  }
}
