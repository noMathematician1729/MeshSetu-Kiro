import 'dart:async';
import 'dart:typed_data';

import '../model/model.dart';
import '../protocol/frame.dart';
import '../protocol/relay_engine.dart';
import '../protocol/protocol_metrics.dart';
import 'async_lock.dart';
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
  Stream<PeerSessionState> get state;
  Future<bool> send(Uint8List bytes, {bool withResponse = true});
  Future<void> close();
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
  Stream<PeerSessionState> get state => _session.stateStream;

  @override
  Future<bool> send(Uint8List bytes, {bool withResponse = true}) async {
    try {
      await _session.send(bytes, withResponse: withResponse);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> close() => _session.close();
}

typedef MetricsListener = void Function(List<RelayMetric> metrics);

/// Port of `in.meshsetu.ble.MeshTransportCoordinator` (Kotlin
/// `MeshTransport.kt`).
///
/// Deviations from the Kotlin source:
/// - No `CoroutineScope` parameter — Dart `Stream.listen` callbacks already
///   run on the event loop; there's no separate dispatcher to launch onto.
/// - Depends on [PeerLink] instead of [GattPeerSession] directly (see above).
class MeshTransportCoordinator implements MeshTransport {
  MeshTransportCoordinator({
    required this.server,
    required this.relay,
    this.localHello,
    this.frameInterceptor,
    MetricsListener? onMetrics,
  }) : _onMetrics = onMetrics ?? ((_) {}) {
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

  static const int maxReplicationPeers = 2;

  final MeshGattServer server;
  final MeshRelayEngine relay;
  final Hello? localHello;
  final LossyFrameInterceptor? frameInterceptor;
  final MetricsListener _onMetrics;

  final StreamController<ReceivedObject> _receivedController =
      StreamController<ReceivedObject>.broadcast();
  final StreamController<List<PeerState>> _peersController =
      StreamController<List<PeerState>>.broadcast();
  List<PeerState> _peers = [];

  final Map<String, PeerLink> _sessions = {};
  final Map<String, List<StreamSubscription<Object?>>> _sessionSubscriptions =
      {};
  StreamSubscription<Object?>? _serverSubscription;
  final AsyncLock _pumpLock = AsyncLock();
  final AsyncLock _relayLock = AsyncLock();

  @override
  Stream<ReceivedObject> get incoming => _receivedController.stream;

  @override
  Stream<List<PeerState>> get peerState => _peersController.stream;

  Future<void> start() async {
    await server.start();
    _serverSubscription = server.incoming.listen((frame) {
      unawaited(
        _relayLock.synchronized(() async {
          try {
            if (!_acceptsHello(frame.bytes)) return;
            final result = await relay.receive(frame.deviceId, frame.bytes);
            _onMetrics(result.metrics);
            for (final controlFrame in result.controlFrames) {
              await server.notifyAwait(frame.deviceId, controlFrame);
            }
            await _pump();
          } finally {
            server.acknowledge(frame);
          }
        }),
      );
    });
  }

  bool hasPeer(String peerId) => _sessions.containsKey(peerId);

  void attach(
    String peerId,
    PeerLink link, {
    required int siteFingerprint,
    int? rssi,
  }) {
    final old = _sessions[peerId];
    _detach(peerId);
    if (old != null) unawaited(old.close());

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

    final subscriptions = <StreamSubscription<Object?>>[
      link.state.listen((state) {
        if (state == PeerSessionState.disconnected ||
            state == PeerSessionState.failed) {
          _detach(peerId);
        }
      }),
    ];

    final hello = localHello;
    if (hello != null) {
      unawaited(
        link.send(
          FrameCodec.encode(
            MeshFrame(
              type: FrameType.hello,
              priority: 0,
              flags: 0,
              objectId: hello.ephemeralNodeId,
              sequence: 0,
              count: 1,
              payload: HelloCodec.encode(hello),
            ),
          ),
        ),
      );
    }
    subscriptions.add(
      link.incoming.listen((bytes) {
        unawaited(
          _relayLock.synchronized(() async {
            if (!_acceptsHello(bytes)) {
              await link.close();
              return;
            }
            final result = await relay.receive(peerId, bytes);
            _onMetrics(result.metrics);
            for (final controlFrame in result.controlFrames) {
              await link.send(controlFrame, withResponse: true);
            }
            await _pump();
          }),
        );
      }),
    );
    _sessionSubscriptions[peerId] = subscriptions;
  }

  @override
  Future<SendTicket> send(MeshEnvelope value) =>
      _relayLock.synchronized(() async {
        await relay.submit(value);
        await _pump();
        return SendTicket(value.objectId);
      });

  /// Requests missing chunks from each attached peer, drains any newly
  /// queued outbound objects, and forwards accumulated metrics. Meant to be
  /// called periodically (the Kotlin source's `MeshEventService` calls this
  /// on a 2s loop alongside its scan cycle).
  Future<void> tick() => _relayLock.synchronized(() async {
    for (final entry in _sessions.entries.toList()) {
      for (final frame in relay.missingForPeer(entry.key)) {
        await entry.value.send(frame, withResponse: true);
      }
    }
    await _pump();
    _onMetrics(relay.drainMetrics());
  });

  Future<void> _pump() => _pumpLock.synchronized(() async {
    relay.retryExpired();
    if (_sessions.isEmpty) return;
    final peers = _sessions.entries.take(maxReplicationPeers).toList();
    if (peers.isEmpty) return;
    while (true) {
      final objectToSend = relay.nextOutbound();
      if (objectToSend == null) return;
      var sentToAny = false;
      var deferred = false;
      for (final peer in peers) {
        try {
          final frames = fragment(
            objectId: objectToSend.objectId,
            priority: objectToSend.trafficClass.rank,
            encrypted: objectToSend.bytes,
            mtu: peer.value.mtu,
          );
          var allOk = true;
          for (final frame in frames) {
            final encoded = FrameCodec.encode(frame);
            final intercepted = frameInterceptor == null
                ? encoded
                : frameInterceptor!.apply(encoded);
            if (intercepted == null) {
              allOk = false;
              break;
            }
            final ok = await peer.value.send(intercepted, withResponse: true);
            if (!ok) {
              allOk = false;
              break;
            }
          }
          if (allOk) {
            relay.markSent(objectToSend, peer.key);
            sentToAny = true;
          }
        } on ArgumentError catch (_) {
          // fragment() rejects an object that can't fit this peer's MTU
          // budget; defer voice evidence (graceful degradation) instead of
          // blocking the queue on it.
          if (objectToSend.trafficClass == TrafficClass.voiceEvidence) {
            relay.defer(objectToSend);
            deferred = true;
            _onMetrics([
              RelayMetric(
                'deferred_mtu',
                objectId: objectToSend.objectId,
                peerId: peer.key,
              ),
            ]);
          }
        }
      }
      if (!sentToAny) {
        if (!deferred) relay.requeue(objectToSend);
        return;
      }
    }
  });

  Future<void> stop() async {
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    for (final subs in _sessionSubscriptions.values) {
      for (final s in subs) {
        await s.cancel();
      }
    }
    _sessionSubscriptions.clear();
    await _relayLock.idle;
    for (final link in _sessions.values.toList()) {
      await link.close();
    }
    _sessions.clear();
    await server.stop();
    _peers = [];
    if (!_peersController.isClosed) _peersController.add(_peers);
    await _receivedController.close();
    await _peersController.close();
  }

  void _detach(String peerId) {
    _sessions.remove(peerId);
    final subs = _sessionSubscriptions.remove(peerId);
    if (subs != null) {
      for (final s in subs) {
        s.cancel();
      }
    }
    if (_peers.any((p) => p.peerId == peerId)) {
      _peers = [
        for (final p in _peers)
          if (p.peerId != peerId) p,
      ];
      _peersController.add(_peers);
    }
  }

  bool _acceptsHello(Uint8List bytes) {
    final MeshFrame frame;
    try {
      frame = FrameCodec.decode(bytes);
    } catch (_) {
      return true;
    }
    if (frame.type != FrameType.hello) return true;
    final remote = HelloCodec.decode(frame.payload);
    if (remote == null) return false;
    final hello = localHello;
    return hello == null || remote.siteFingerprint == hello.siteFingerprint;
  }
}
