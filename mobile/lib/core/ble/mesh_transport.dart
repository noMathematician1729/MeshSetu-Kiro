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

/// Server-side peer: receives frames through the shared server stream and
/// sends relay traffic through notifications.
class GattServerPeerLink implements PeerLink {
  GattServerPeerLink(this._server, this.deviceId, this.mtu);

  final MeshGattServer _server;
  final String deviceId;

  @override
  final int mtu;

  @override
  Stream<Uint8List> get incoming => const Stream<Uint8List>.empty();

  @override
  Stream<PeerSessionState> get state => _server
      .connectionStateFor(deviceId)
      .map(
        (connected) =>
            connected ? PeerSessionState.ready : PeerSessionState.disconnected,
      );

  @override
  Future<bool> send(Uint8List bytes, {bool withResponse = true}) async {
    try {
      return await _server.notifyAwait(deviceId, bytes);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> close() => _server.disconnectPeer(deviceId);
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
    _peersController = StreamController<List<PeerState>>.broadcast();
    relay.addPersistListener((envelope, peerId, encryptedBytes) {
      _receivedController.add(
        ReceivedObject(
          envelope: envelope,
          peerId: peerId,
          receivedAtMs: DateTime.now().millisecondsSinceEpoch,
          encryptedBytes: Uint8List.fromList(encryptedBytes),
        ),
      );
    });
  }

  static const int maxReplicationPeers = 2;
  static const int maxPeerConnections = 4;

  final MeshGattServer server;
  final MeshRelayEngine relay;
  final Hello? localHello;
  LossyFrameInterceptor? frameInterceptor;
  final MetricsListener _onMetrics;

  final StreamController<ReceivedObject> _receivedController =
      StreamController<ReceivedObject>.broadcast();
  late final StreamController<List<PeerState>> _peersController;
  List<PeerState> _peers = [];

  final Map<String, PeerLink> _sessions = {};
  final Map<String, List<StreamSubscription<Object?>>> _sessionSubscriptions =
      {};
  StreamSubscription<Object?>? _serverSubscription;
  StreamSubscription<String>? _serverPeerSubscription;
  StreamSubscription<String>? _serverUnsubscribedPeerSubscription;
  final Set<String> _serverPeersStarting = {};
  final Map<int, String> _lastInboundPeerByObject = {};

  /// Peers that have sent at least one decodable, same-site HELLO frame
  /// (Bible audit Task 5). A peer connected via the UUID-only fallback
  /// (Task 4) or one that skips HELLO entirely is not in this set; today
  /// that only emits `peer_unverified_site` on every non-HELLO frame it
  /// sends (log-only, per plan) rather than dropping the connection, so
  /// this can be watched on real devices before flipping to strict.
  final Set<String> _helloVerifiedPeers = {};
  // Lock order is relay -> pump. No pump-held path may await the relay lock.
  final AsyncLock _pumpLock = AsyncLock();
  final AsyncLock _relayLock = AsyncLock();
  bool _stopped = false;
  bool _pumpActive = false;

  @override
  Stream<ReceivedObject> get incoming => _receivedController.stream;

  @override
  Stream<List<PeerState>> get peerState => Stream.multi((controller) {
    controller.add(List<PeerState>.unmodifiable(_peers));
    final subscription = _peersController.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);

  Future<void> start() async {
    _stopped = false;
    _serverPeerSubscription = server.readyPeerIds.listen((peerId) {
      if (!_stopped) unawaited(_ensureServerPeer(peerId));
    });
    _serverUnsubscribedPeerSubscription = server.unsubscribedPeerIds.listen((
      peerId,
    ) {
      // Let MeshGattServer update its subscription set before checking
      // capacity or promoting another rejected peer.
      scheduleMicrotask(() {
        if (_stopped) return;
        final link = _sessions[peerId];
        _detach(peerId, expected: link);
        unawaited(link?.close());
      });
    });
    _serverSubscription = server.incoming.listen((frame) {
      unawaited(
        _relayLock.synchronized(() async {
          try {
            if (_stopped) return;
            await _ensureServerPeer(frame.deviceId);
            if (_stopped) return;
            if (!_sessions.containsKey(frame.deviceId)) return;
            if (!_acceptsHello(frame.deviceId, frame.bytes)) {
              final link = _sessions[frame.deviceId];
              server.rejectPeer(frame.deviceId);
              _detach(frame.deviceId, expected: link, promoteRejected: false);
              unawaited(link?.close());
              return;
            }
            _onMetrics([
              RelayMetric(
                'frame_received',
                peerId: frame.deviceId,
                value: frame.bytes.length,
              ),
              RelayMetric(
                'frame_rx',
                peerId: frame.deviceId,
                value: frame.bytes.length,
              ),
            ]);
            final result = await relay.receive(frame.deviceId, frame.bytes);
            _rememberInboundPeers(frame.deviceId, result.metrics);
            _markPeerSeen(frame.deviceId);
            _onMetrics(result.metrics);
            for (final controlFrame in result.controlFrames) {
              await _sendServerControl(frame.deviceId, controlFrame);
            }
            await _pump();
          } catch (error) {
            _reportAsyncFailure(frame.deviceId, error);
          } finally {
            server.acknowledge(frame);
          }
        }),
      );
    });
    try {
      // Install consumers before exposing the service. A client can subscribe
      // and write immediately after addService completes; subscribing after
      // server.start() would leave a narrow frame-loss window.
      await server.start();
    } catch (_) {
      await _serverPeerSubscription?.cancel();
      _serverPeerSubscription = null;
      await _serverUnsubscribedPeerSubscription?.cancel();
      _serverUnsubscribedPeerSubscription = null;
      await _serverSubscription?.cancel();
      _serverSubscription = null;
      rethrow;
    }
  }

  Future<void> _ensureServerPeer(String peerId) async {
    if (_stopped ||
        server.isPeerRejected(peerId) ||
        !server.hasLiveSubscription(peerId) ||
        _sessions.containsKey(peerId) ||
        !_serverPeersStarting.add(peerId)) {
      return;
    }
    try {
      final mtu = await server.mtuFor(peerId);
      if (_stopped ||
          !server.hasLiveSubscription(peerId) ||
          _sessions.containsKey(peerId)) {
        return;
      }
      if (_sessions.length >= maxPeerConnections) {
        server.rejectPeer(peerId);
        _onMetrics([RelayMetric('peer_rejected_capacity', peerId: peerId)]);
        unawaited(server.disconnectPeer(peerId));
        return;
      }
      if (!server.admitPeer(peerId)) return;
      attach(
        peerId,
        GattServerPeerLink(server, peerId, mtu),
        siteFingerprint: localHello?.siteFingerprint ?? 0,
      );
    } catch (_) {
      if (!_stopped) {
        _onMetrics([RelayMetric('server_peer_attach_failed', peerId: peerId)]);
      }
    } finally {
      _serverPeersStarting.remove(peerId);
    }
  }

  bool hasPeer(String peerId) => _sessions.containsKey(peerId);

  int get peerCount => _sessions.length;

  void attach(
    String peerId,
    PeerLink link, {
    required int siteFingerprint,
    int? rssi,
  }) {
    if (_stopped) {
      unawaited(link.close());
      return;
    }
    final old = _sessions[peerId];
    if (old == null && _sessions.length >= maxPeerConnections) {
      if (link is GattServerPeerLink) server.rejectPeer(peerId);
      _onMetrics([RelayMetric('peer_rejected_capacity', peerId: peerId)]);
      unawaited(link.close());
      return;
    }
    _detach(peerId, expected: old, promoteRejected: false);
    if (old != null) unawaited(old.close());

    _sessions[peerId] = link;
    final peerCountBefore = _sessions.length - 1;
    final schedulerHasQueuedObject = relay.scheduler.size() > 0;
    _peers = [
      for (final p in _peers)
        if (p.peerId != peerId) p,
      PeerState(
        peerId: peerId,
        siteFingerprint: siteFingerprint,
        connected: true,
        mtu: link.mtu,
        rssi: rssi,
        queuedObjects: relay.scheduler.size(),
        lastSeenMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    _emitPeers();
    _onMetrics([
      RelayMetric('peer_connected', peerId: peerId, value: link.mtu),
      RelayMetric('peer_session_ready', peerId: peerId, value: link.mtu),
      RelayMetric(
        'peer_count_changed',
        peerId: peerId,
        value: _sessions.length,
        detail: '$peerCountBefore->${_sessions.length}',
      ),
    ]);

    final subscriptions = <StreamSubscription<Object?>>[
      link.state.listen((state) {
        if (state == PeerSessionState.disconnected ||
            state == PeerSessionState.failed) {
          _detach(peerId, expected: link);
          unawaited(link.close());
        }
      }),
    ];

    // Subscribe before sending HELLO. The peer can answer synchronously after
    // the write completes; installing this listener later loses that first
    // notification on fast links.
    subscriptions.add(
      link.incoming.listen((bytes) {
        unawaited(
          _relayLock.synchronized(() async {
            try {
              if (_stopped || _sessions[peerId] != link) return;
              if (!_acceptsHello(peerId, bytes)) {
                _detach(peerId, expected: link);
                await link.close();
                return;
              }
              _onMetrics([
                RelayMetric(
                  'frame_received',
                  peerId: peerId,
                  value: bytes.length,
                ),
                RelayMetric('frame_rx', peerId: peerId, value: bytes.length),
              ]);
              final result = await relay.receive(peerId, bytes);
              _rememberInboundPeers(peerId, result.metrics);
              _markPeerSeen(peerId);
              _onMetrics(result.metrics);
              for (final controlFrame in result.controlFrames) {
                await _sendControl(peerId, link, controlFrame);
              }
              await _pump();
            } catch (error) {
              _reportAsyncFailure(peerId, error);
            }
          }),
        );
      }),
    );
    _sessionSubscriptions[peerId] = subscriptions;

    final hello = localHello;
    if (hello != null) {
      unawaited(
        _sendControl(
          peerId,
          link,
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
    if (schedulerHasQueuedObject) _wakeScheduler('peer_ready');
  }

  @override
  Future<SendTicket> send(MeshEnvelope value) async {
    // Let an urgent object enter the durable scheduler while a lower-priority
    // frame is awaiting the radio. The pump notices it between frames.
    if (_pumpActive) {
      final encrypted = await relay.crypto.encrypt(value);
      relay.requeue(encrypted);
      _onMetrics([RelayMetric('outbox_enqueued', objectId: value.objectId)]);
      unawaited(_pump());
      return SendTicket(value.objectId);
    }
    return _relayLock.synchronized(() async {
      await relay.submit(value);
      _onMetrics([RelayMetric('outbox_enqueued', objectId: value.objectId)]);
      await _pump();
      return SendTicket(value.objectId);
    });
  }

  /// Produces the authenticated packet representation used by an online
  /// gateway. The mesh send path encrypts independently, so this method never
  /// changes scheduler ownership or peer delivery.
  Future<EncryptedObject> encryptForGateway(MeshEnvelope value) =>
      relay.crypto.encrypt(value);

  /// Requests missing chunks from each attached peer, drains any newly
  /// queued outbound objects, and forwards accumulated metrics. Meant to be
  /// called periodically (the Kotlin source's `MeshEventService` calls this
  /// on a 2s loop alongside its scan cycle).
  Future<void> tick() => _relayLock.synchronized(() async {
    for (final entry in _sessions.entries.toList()) {
      for (final frame in relay.missingForPeer(entry.key)) {
        await _sendControl(entry.key, entry.value, frame);
      }
    }
    await _pump();
    _onMetrics(relay.drainMetrics());
  });

  Future<void> _pump() => _pumpLock.synchronized(() async {
    _pumpActive = true;
    try {
      relay.retryExpired();
      if (_stopped || _sessions.isEmpty) return;
      while (true) {
        final objectToSend = relay.nextOutbound();
        if (objectToSend == null) return;
        _onMetrics([
          RelayMetric(
            'scheduler_selected_object',
            objectId: objectToSend.objectId,
            detail: objectToSend.trafficClass.name,
          ),
        ]);
        var sentToAny = false;
        var mtuRejectedPeers = 0;
        var attemptedPeers = 0;
        var preempted = false;
        var successfulPeers = 0;
        final sourcePeer = _lastInboundPeerByObject[objectToSend.objectId];
        final peers = _sessions.entries
            .where((entry) => entry.key != sourcePeer)
            .toList();
        if (peers.isEmpty) {
          relay.requeue(objectToSend);
          return;
        }
        for (final peer in peers) {
          if (successfulPeers >= maxReplicationPeers) break;
          attemptedPeers++;
          _onMetrics([
            RelayMetric(
              'scheduler_selected_peer',
              objectId: objectToSend.objectId,
              peerId: peer.key,
              value: peer.value.mtu,
            ),
          ]);
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
              _onMetrics([
                RelayMetric(
                  'frame_write_accepted_locally',
                  objectId: objectToSend.objectId,
                  peerId: peer.key,
                  value: intercepted.length,
                  detail: ok ? 'accepted' : 'rejected',
                ),
              ]);
              if (!ok) {
                allOk = false;
                break;
              }
              if (relay.scheduler.hasHigherPriorityThan(
                objectToSend.trafficClass,
              )) {
                preempted = true;
                break;
              }
            }
            if (preempted) break;
            if (allOk) {
              relay.markSent(objectToSend, peer.key);
              sentToAny = true;
              successfulPeers++;
              _onMetrics([
                RelayMetric(
                  'frames_sent',
                  objectId: objectToSend.objectId,
                  peerId: peer.key,
                  value: frames.length,
                  detail: 'local_writes_accepted_waiting_for_ack',
                ),
                RelayMetric(
                  'frame_tx',
                  objectId: objectToSend.objectId,
                  peerId: peer.key,
                  value: frames.length,
                ),
              ]);
            } else {
              _onMetrics([
                RelayMetric(
                  'send_failed',
                  objectId: objectToSend.objectId,
                  peerId: peer.key,
                ),
              ]);
            }
          } on ArgumentError catch (_) {
            // fragment() rejects an object that can't fit this peer's MTU
            // budget (or, for a malformed/oversized object, any budget).
            // Defer instead of blocking the queue on it — voice evidence
            // degrades gracefully by design, and a non-voice object that
            // cannot fragment for any peer will never succeed by retrying,
            // so it must not spin the pump forever either.
            mtuRejectedPeers++;
            _onMetrics([
              RelayMetric(
                'deferred_mtu',
                objectId: objectToSend.objectId,
                peerId: peer.key,
              ),
            ]);
          } catch (_) {
            _onMetrics([
              RelayMetric(
                'send_failed',
                objectId: objectToSend.objectId,
                peerId: peer.key,
              ),
            ]);
          }
        }
        if (preempted) {
          relay.requeue(objectToSend);
          continue;
        }
        if (!sentToAny) {
          if (mtuRejectedPeers == attemptedPeers && attemptedPeers > 0) {
            relay.defer(objectToSend);
          } else {
            relay.requeue(objectToSend);
          }
          return;
        }
      }
    } finally {
      _pumpActive = false;
    }
  });

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _serverPeerSubscription?.cancel();
    _serverPeerSubscription = null;
    await _serverUnsubscribedPeerSubscription?.cancel();
    _serverUnsubscribedPeerSubscription = null;
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    for (final subs in _sessionSubscriptions.values) {
      for (final s in subs) {
        await s.cancel();
      }
    }
    _sessionSubscriptions.clear();
    await _relayLock.idle;
    await _pumpLock.idle;
    for (final link in _sessions.values.toList()) {
      await link.close();
    }
    _sessions.clear();
    _serverPeersStarting.clear();
    _lastInboundPeerByObject.clear();
    _helloVerifiedPeers.clear();
    await server.stop();
    _peers = [];
    _emitPeers();
    await _receivedController.close();
    await _peersController.close();
  }

  void _detach(
    String peerId, {
    PeerLink? expected,
    bool promoteRejected = true,
  }) {
    final current = _sessions[peerId];
    if (current == null || (expected != null && current != expected)) return;
    _helloVerifiedPeers.remove(peerId);
    final peerCountBefore = _sessions.length;
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
      _emitPeers();
      _onMetrics([
        RelayMetric('peer_disconnected', peerId: peerId),
        RelayMetric(
          'peer_count_changed',
          peerId: peerId,
          value: _sessions.length,
          detail: '$peerCountBefore->${_sessions.length}',
        ),
      ]);
      _wakeScheduler('peer_disconnected');
    }
    if (promoteRejected && !_stopped) _promoteRejectedPeers();
  }

  void _promoteRejectedPeers() {
    if (_sessions.length + _serverPeersStarting.length >= maxPeerConnections) {
      return;
    }
    for (final peerId in server.rejectedPeerIds) {
      if (_sessions.length + _serverPeersStarting.length >=
          maxPeerConnections) {
        return;
      }
      if (server.hasLiveSubscription(peerId)) {
        if (server.makePeerEligible(peerId)) {
          unawaited(_ensureServerPeer(peerId));
        }
      } else {
        // A capacity rejection is physically disconnected on Android. Ask
        // the GATT server to reconnect it; the client's normal CCCD write
        // will clear the quarantine and re-enter this admission path.
        unawaited(server.reconnectPeer(peerId));
      }
    }
  }

  void _emitPeers() {
    if (!_peersController.isClosed) {
      _peersController.add(List<PeerState>.unmodifiable(_peers));
    }
  }

  void _wakeScheduler(String reason) {
    if (_stopped) return;
    unawaited(_runSchedulerWake(reason));
  }

  Future<void> _runSchedulerWake(String reason) async {
    try {
      await _relayLock.synchronized(() async {
        if (_stopped) return;
        _onMetrics([RelayMetric('scheduler_wake', detail: reason)]);
        await _pump();
        _onMetrics(relay.drainMetrics());
      });
    } catch (error) {
      _reportAsyncFailure(null, error, kind: 'scheduler_failed');
    }
  }

  void _reportAsyncFailure(
    String? peerId,
    Object error, {
    String kind = 'frame_processing_failed',
  }) {
    try {
      _onMetrics([RelayMetric(kind, peerId: peerId, detail: '$error')]);
    } catch (_) {
      // Observability must not reintroduce the uncaught async failure.
    }
  }

  void _markPeerSeen(String peerId) {
    final index = _peers.indexWhere((peer) => peer.peerId == peerId);
    if (index == -1) return;
    final peer = _peers[index];
    _peers[index] = PeerState(
      peerId: peer.peerId,
      siteFingerprint: peer.siteFingerprint,
      connected: peer.connected,
      mtu: peer.mtu,
      rssi: peer.rssi,
      queuedObjects: relay.scheduler.size(),
      lastSeenMs: DateTime.now().millisecondsSinceEpoch,
    );
    _emitPeers();
  }

  void _rememberInboundPeers(String peerId, List<RelayMetric> metrics) {
    for (final metric in metrics) {
      if (metric.kind != 'object_complete' || metric.objectId == null) {
        continue;
      }
      _lastInboundPeerByObject[metric.objectId!] = peerId;
    }
    // ponytail: bounded source-peer history avoids immediate bounce loops;
    // replace with per-outbox route state if forwarding policy becomes richer.
    while (_lastInboundPeerByObject.length > 4096) {
      _lastInboundPeerByObject.remove(_lastInboundPeerByObject.keys.first);
    }
  }

  Future<void> _sendServerControl(String peerId, Uint8List frame) async {
    try {
      _reportControlResult(
        peerId,
        frame,
        await server.notifyAwait(peerId, frame),
      );
    } catch (_) {
      _reportControlResult(peerId, frame, false);
    }
  }

  Future<void> _sendControl(
    String peerId,
    PeerLink link,
    Uint8List frame,
  ) async {
    try {
      _reportControlResult(
        peerId,
        frame,
        await link.send(frame, withResponse: true),
      );
    } catch (_) {
      _reportControlResult(peerId, frame, false);
    }
  }

  void _reportControlResult(String peerId, Uint8List frame, bool sent) {
    int? custodyAckObjectId;
    try {
      final decoded = FrameCodec.decode(frame);
      if (decoded.type == FrameType.custodyAck) {
        custodyAckObjectId = decoded.objectId;
      }
    } catch (_) {
      // A malformed local control frame is reported through the send result.
    }

    if (sent) {
      if (custodyAckObjectId != null) {
        _onMetrics([
          RelayMetric(
            'custody_ack_sent',
            objectId: custodyAckObjectId,
            peerId: peerId,
          ),
        ]);
      }
      return;
    }

    _onMetrics([
      RelayMetric(
        'control_send_failed',
        objectId: custodyAckObjectId,
        peerId: peerId,
      ),
      if (custodyAckObjectId != null)
        RelayMetric(
          'custody_ack_send_failed',
          objectId: custodyAckObjectId,
          peerId: peerId,
        ),
    ]);
  }

  bool _acceptsHello(String peerId, Uint8List bytes) {
    final MeshFrame frame;
    try {
      frame = FrameCodec.decode(bytes);
    } catch (_) {
      _reportUnverifiedTraffic(peerId);
      return true;
    }
    if (frame.type != FrameType.hello) {
      _reportUnverifiedTraffic(peerId);
      return true;
    }
    final remote = HelloCodec.decode(frame.payload);
    if (remote == null) return false;
    final hello = localHello;
    final sameSite =
        hello == null || remote.siteFingerprint == hello.siteFingerprint;
    if (sameSite) _helloVerifiedPeers.add(peerId);
    return sameSite;
  }

  /// Log-only enforcement (Bible audit Task 5): a peer that has never sent a
  /// decodable, same-site HELLO is still allowed to relay today — flipping
  /// this to strict (dropping the connection instead) is the next step once
  /// `peer_unverified_site` has been observed on real devices to confirm it
  /// does not fire for legitimate peers using the UUID-only fallback path
  /// before their HELLO round-trip completes.
  void _reportUnverifiedTraffic(String peerId) {
    if (_helloVerifiedPeers.contains(peerId)) return;
    _onMetrics([RelayMetric('peer_unverified_site', peerId: peerId)]);
  }
}
