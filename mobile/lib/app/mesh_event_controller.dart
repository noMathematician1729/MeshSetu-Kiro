import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../core/ble/ble_discovery.dart';
import '../core/ble/device_key_store.dart';
import '../core/ble/gatt_peer_session.dart';
import '../core/ble/gatt_server.dart';
import '../core/ble/mesh_gatt.dart';
import '../core/ble/mesh_transport.dart';
import '../core/model/model.dart';
import '../core/protocol/frame.dart';
import '../core/protocol/protocol_metrics.dart';
import '../core/protocol/relay_engine.dart';
import '../core/protocol/secure_envelope.dart';

/// Port of `in.meshsetu.app.MeshEventService`'s mesh-orchestration logic
/// (Kotlin `MeshEventService.kt` — `startMesh`, `sendTestObject`).
///
/// The foreground task owns one instance of this controller so scanning and
/// relay processing continue after the Activity is paused or destroyed.
class MeshEventController {
  static const String siteId = 'demo-site';
  static const String siteNamespace = 'demo';
  static const int capabilityRelay = 1;
  static const int capabilityVoice = 1 << 3;

  /// Demo manifest used by the foreground task. A real site should replace
  /// this with its signed anchor map before deployment.
  static ZoneResolver get demoZoneResolver => ZoneResolver({
    'gate-b': const ZoneAnchor(anchorId: 'gate-b', logicalZone: 'Gate-B'),
    'gate-east': const ZoneAnchor(
      anchorId: 'gate-east',
      logicalZone: 'Gate-East',
    ),
  });

  MeshEventController({
    this.onPeerState,
    this.onMeshStatus,
    this.onMetrics,
    this.onBeaconObservations,
    this.zoneResolver,
    this.onZoneEstimate,
  });

  final void Function(List<PeerState> peers)? onPeerState;
  final void Function(String status)? onMeshStatus;
  final void Function(List<RelayMetric> metrics)? onMetrics;
  final void Function(List<BeaconObservation> observations)?
  onBeaconObservations;
  final ZoneResolver? zoneResolver;
  final void Function(ZoneEstimate estimate)? onZoneEstimate;

  MeshTransportCoordinator? _coordinator;
  int _localToken = 0;
  IOSink? _metricSink;
  JsonLineMetricSink? _jsonMetricSink;
  bool _looping = false;
  bool _starting = false;
  bool _stopRequested = false;
  Completer<void>? _scanCancel;
  Future<void>? _scanFuture;
  final Map<String, int> _retryAfterMs = {};
  final Set<Future<void>> _connectionAttempts = {};
  final Set<String> _connectingPeerIds = {};
  StreamSubscription<List<PeerState>>? _peerStateSubscription;

  MeshTransportCoordinator? get coordinator => _coordinator;

  void setDebugLossInjection(bool enabled) {
    final coordinator = _coordinator;
    if (coordinator == null) return;
    coordinator.frameInterceptor = enabled
        ? LossyFrameInterceptor(dropEvery: 5, corruptEvery: 7)
        : null;
  }

  Future<void> start() async {
    if (_looping || _starting) return;
    _starting = true;
    _stopRequested = false;
    MeshTransportCoordinator? coordinator;
    IOSink? metricSink;
    try {
      final siteFingerprint = MeshGatt.siteFingerprint(
        siteId,
        namespace: siteNamespace,
      );
      _localToken = _randomNonZero32();

      final documentsDir = await getApplicationDocumentsDirectory();
      final metricFile = File('${documentsDir.path}/mesh-metrics.ndjson');
      metricSink = metricFile.openWrite(mode: FileMode.append);
      _metricSink = metricSink;
      _jsonMetricSink = JsonLineMetricSink(metricSink);

      final siteKeyBytes = await DeviceKeyStore.getOrCreateSiteKey(
        siteId,
        SiteKeyProvisioning.demoKey(siteId),
      );
      final relay = MeshRelayEngine(
        siteId: siteId,
        crypto: AeadEnvelope(siteKeyBytes),
        store: FileRelayStore(Directory('${documentsDir.path}/mesh-relay')),
        clockMs: () => DateTime.now().millisecondsSinceEpoch,
      );
      final server = MeshGattServer();
      final hello = Hello(
        siteFingerprint: siteFingerprint,
        ephemeralNodeId: _localToken,
        capabilities: capabilityRelay | capabilityVoice,
        nowEpochSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      coordinator = MeshTransportCoordinator(
        server: server,
        relay: relay,
        localHello: hello,
        onMetrics: _reportMetrics,
      );
      await coordinator.start();
      if (_stopRequested) throw StateError('mesh start cancelled');
      _coordinator = coordinator;
      _peerStateSubscription = coordinator.peerState.listen((peers) {
        onPeerState?.call(peers);
      });

      await MeshAdvertiser.start(
        DiscoveryMetadata(
          fingerprint: siteFingerprint,
          connectionToken: _localToken,
          capabilities: capabilityRelay | capabilityVoice,
        ),
      );
      if (_stopRequested) throw StateError('mesh start cancelled');

      _looping = true;
      _scanCancel = Completer<void>();
      _scanFuture = _scanLoop(siteFingerprint, coordinator);
      unawaited(_scanFuture!);
      onMeshStatus?.call('advertising');
    } catch (_) {
      _looping = false;
      _scanCancel?.complete();
      _scanCancel = null;
      await _scanFuture;
      _scanFuture = null;
      await Future.wait(_connectionAttempts.toList());
      _connectingPeerIds.clear();
      await _peerStateSubscription?.cancel();
      _peerStateSubscription = null;
      _coordinator = null;
      await coordinator?.stop();
      try {
        await MeshAdvertiser.stop();
      } catch (_) {
        // Advertising may not have started yet.
      }
      await metricSink?.close();
      _metricSink = null;
      _jsonMetricSink = null;
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> _scanLoop(
    int siteFingerprint,
    MeshTransportCoordinator coordinator,
  ) async {
    while (_looping) {
      List<DiscoveredPeer> peers;
      try {
        onMeshStatus?.call('scanning');
        peers = await MeshScanner.scan(
          expectedFingerprint: siteFingerprint,
          cancel: _scanCancel?.future,
        );
      } catch (_) {
        if (!_looping) return;
        if (!await _waitOrStop(const Duration(seconds: 2))) return;
        continue;
      }
      _reportMetrics([
        for (final peer in peers)
          RelayMetric(
            'scan_found',
            peerId: peer.device.deviceId,
            value: peer.device.rssi,
          ),
      ]);
      final candidates = <DiscoveredPeer>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      final capacity =
          MeshTransportCoordinator.maxPeerConnections -
          coordinator.peerCount -
          _connectingPeerIds.length;
      for (final peer in peers) {
        if (candidates.length >= capacity) {
          break;
        }
        if (capacity <= 0) break;
        if (!shouldInitiate(_localToken, peer.metadata.connectionToken) ||
            coordinator.hasPeer(peer.device.deviceId) ||
            _connectingPeerIds.contains(peer.device.deviceId) ||
            (_retryAfterMs[peer.device.deviceId] ?? 0) > now) {
          continue;
        }
        candidates.add(peer);
      }
      for (final peer in candidates) {
        _startConnection(peer, coordinator);
      }
      if (!_looping) return;
      try {
        final beacons = await MeshBeaconScanner.scan(
          cancel: _scanCancel?.future,
        );
        if (beacons.isNotEmpty) {
          _reportMetrics([
            for (final beacon in beacons)
              RelayMetric(
                'beacon_found',
                peerId: beacon.anchorId,
                value: beacon.rssi,
              ),
          ]);
        }
        onBeaconObservations?.call(beacons);
        final resolver = zoneResolver ?? ZoneResolver(const {});
        onZoneEstimate?.call(
          resolver.estimate(beacons, DateTime.now().millisecondsSinceEpoch),
        );
      } catch (_) {
        // Peer discovery remains useful if beacon scanning is unavailable.
      }
      if (!_looping) return;
      try {
        await coordinator.tick();
      } catch (_) {
        // A transient peer failure must not terminate the long-running scan.
      }
      onMeshStatus?.call('idle');
      if (!await _waitOrStop(const Duration(seconds: 2))) return;
    }
  }

  Future<bool> _waitOrStop(Duration duration) async {
    final cancel = _scanCancel?.future;
    if (cancel == null) {
      await Future<void>.delayed(duration);
      return _looping;
    }
    await Future.any<void>([Future<void>.delayed(duration), cancel]);
    return _looping;
  }

  Future<void> _connectPeer(
    DiscoveredPeer peer,
    MeshTransportCoordinator coordinator,
  ) async {
    GattPeerSession? session;
    try {
      session = GattPeerSession.open(peer.device.deviceId);
      await session.awaitReady().timeout(const Duration(seconds: 8));
      if (!_looping) {
        await session.close();
        return;
      }
      coordinator.attach(
        peer.device.deviceId,
        GattPeerSessionLink(session),
        siteFingerprint: peer.metadata.fingerprint,
        rssi: peer.device.rssi,
      );
      _retryAfterMs.remove(peer.device.deviceId);
    } catch (_) {
      _retryAfterMs[peer.device.deviceId] =
          DateTime.now().millisecondsSinceEpoch + 10000;
      unawaited(session?.close());
    }
  }

  void _startConnection(
    DiscoveredPeer peer,
    MeshTransportCoordinator coordinator,
  ) {
    if (!_connectingPeerIds.add(peer.device.deviceId)) return;
    final future = _connectPeer(peer, coordinator);
    _connectionAttempts.add(future);
    unawaited(
      future.then(
        (_) {
          _connectionAttempts.remove(future);
          _connectingPeerIds.remove(peer.device.deviceId);
        },
        onError: (Object _, StackTrace __) {
          _connectionAttempts.remove(future);
          _connectingPeerIds.remove(peer.device.deviceId);
        },
      ),
    );
  }

  Future<bool> sendTestObject() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final coordinator = _coordinator;
      if (coordinator != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await coordinator.send(
          MeshEnvelope(
            objectId: _randomNonZero64(),
            eventId: _randomUuidV4(),
            siteId: siteId,
            roomId: 'public',
            createdAtMs: now,
            expiresAtMs: now + 60000,
            hopCount: 0,
            hopLimit: 4,
            priority: PriorityBand.p0Critical,
            payloadType: PayloadType.structuredSos,
            payload: Uint8List.fromList(List.generate(100, (i) => i)),
            originEphemeralId: _localToken,
          ),
        );
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  Future<void> stop() async {
    _stopRequested = true;
    _looping = false;
    if (!(_scanCancel?.isCompleted ?? true)) {
      _scanCancel!.complete();
    }
    final scanFuture = _scanFuture;
    _scanCancel = null;
    _scanFuture = null;
    _retryAfterMs.clear();
    final connectionAttempts = _connectionAttempts.toList();
    final coordinator = _coordinator;
    _coordinator = null;
    final metricSink = _metricSink;
    _metricSink = null;
    try {
      await MeshAdvertiser.stop();
    } catch (_) {
      // Advertising may already have stopped or never started.
    }
    try {
      await scanFuture;
      await Future.wait(connectionAttempts);
      _connectingPeerIds.clear();
      await _peerStateSubscription?.cancel();
      _peerStateSubscription = null;
      await coordinator?.stop();
    } finally {
      await metricSink?.close();
      _jsonMetricSink = null;
      onMeshStatus?.call('stopped');
    }
  }

  void _reportMetrics(List<RelayMetric> metrics) {
    onMetrics?.call(metrics);
    final sink = _jsonMetricSink;
    if (sink == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final metric in metrics) {
      sink.write(
        ProtocolMetric(
          timeMs: now,
          peer: metric.peerId,
          kind: metric.kind,
          value: metric.value,
          detail: metric.objectId?.toString(),
        ),
      );
    }
  }

  static int _randomNonZero32() {
    final value = Random.secure().nextInt(0xFFFFFFFF);
    return value == 0 ? 1 : value;
  }

  static int _randomNonZero64() {
    final random = Random.secure();
    // FrameCodec and protobuf currently use signed int64 accessors. Keep the
    // high bit clear so an object ID has one stable Dart value end to end.
    final high = random.nextInt(1 << 31);
    final low = random.nextInt(1 << 32);
    final value = (high << 32) | low;
    return value == 0 ? 1 : value;
  }

  static String _randomUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
