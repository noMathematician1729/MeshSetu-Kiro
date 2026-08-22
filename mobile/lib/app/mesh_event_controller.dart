import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_ble/universal_ble.dart';

import '../core/ble/ble_discovery.dart';
import '../core/ble/device_key_store.dart';
import '../core/ble/gatt_peer_session.dart';
import '../core/ble/gatt_server.dart';
import '../core/ble/mesh_gatt.dart';
import '../core/ble/mesh_health_watchdog.dart';
import '../core/ble/mesh_transport.dart';
import '../core/ble/scan_pacer.dart';
import '../core/ble/sos_advertisement.dart';
import '../core/model/model.dart';
import '../core/protocol/frame.dart';
import '../core/protocol/protocol_metrics.dart';
import '../core/protocol/relay_engine.dart';
import '../core/protocol/secure_envelope.dart';
import 'test_sos_packet.dart';

/// Port of `in.meshsetu.app.MeshEventService`'s mesh-orchestration logic
/// (Kotlin `MeshEventService.kt` — `startMesh`, `sendTestObject`).
///
/// The foreground task owns one instance of this controller so scanning and
/// relay processing continue after the Activity is paused or destroyed.
final class MeshSiteConfiguration {
  const MeshSiteConfiguration({required this.siteId, required this.namespace});

  static const demo = MeshSiteConfiguration(
    siteId: MeshEventController.demoSiteId,
    namespace: MeshEventController.demoSiteNamespace,
  );

  final String siteId;
  final String namespace;

  /// Keeps existing demo phones interoperable while giving every locally
  /// created event its own BLE discovery and encryption scope.
  factory MeshSiteConfiguration.forSite(String siteId) =>
      siteId == MeshEventController.demoSiteId
      ? demo
      : MeshSiteConfiguration(siteId: siteId, namespace: 'meshsetu-event-v1');

  String encode() => jsonEncode({'siteId': siteId, 'namespace': namespace});

  static MeshSiteConfiguration? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      final siteId = map['siteId'] as String;
      final namespace = map['namespace'] as String;
      if (siteId.trim().isEmpty || namespace.trim().isEmpty) return null;
      return MeshSiteConfiguration(siteId: siteId, namespace: namespace);
    } catch (_) {
      return null;
    }
  }
}

class MeshEventController {
  static const String demoSiteId = 'demo-site';
  static const String demoSiteNamespace = 'demo';
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
    this.configuration = MeshSiteConfiguration.demo,
    this.onPeerState,
    this.onMeshStatus,
    this.onMetrics,
    this.onBeaconObservations,
    this.zoneResolver,
    this.onZoneEstimate,
    this.onCompactSosAlert,
  });

  final MeshSiteConfiguration configuration;
  final void Function(List<PeerState> peers)? onPeerState;
  final void Function(String status)? onMeshStatus;
  final void Function(List<RelayMetric> metrics)? onMetrics;
  final void Function(List<BeaconObservation> observations)?
  onBeaconObservations;
  final ZoneResolver? zoneResolver;
  final void Function(ZoneEstimate estimate)? onZoneEstimate;
  final void Function(MeshSosAdvertisement alert)? onCompactSosAlert;

  MeshTransportCoordinator? _coordinator;
  int _localToken = 0;
  int get localEphemeralId => _localToken;
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
  DiscoveryMetadata? _discoveryMetadata;
  int _sosSequence = 0;
  final Map<String, int> _seenCompactAlerts = {};
  ScanPacer _scanPacer = ScanPacer();
  MeshHealthWatchdog _healthWatchdog = MeshHealthWatchdog();
  int _runGeneration = 0;
  Timer? _advertisingLivenessTimer;
  final Map<String, int> _uuidOnlySightings = {};
  final Map<String, int> _waitingForRemoteDialSinceMs = {};

  /// Consecutive scan cycles a device must be seen as UUID-only (service
  /// UUID matched, no decodable discovery record) before it becomes a
  /// fallback connection candidate (Bible audit Task 4). Requiring repeat
  /// sightings avoids treating a single transient scan-response miss as a
  /// broken peer.
  static const int _uuidOnlyFallbackThreshold = 2;

  /// How long to wait for the peer designated as initiator by
  /// [shouldInitiate] to dial before this device dials anyway (Bible audit
  /// Task 6). Without this, a peer whose own scanning/radio is degraded
  /// never gets called back — connection ownership is one-sided and only
  /// half the pair can ever notice the other went dark.
  static const Duration _fallbackDialDelay = Duration(seconds: 15);

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
    _scanPacer = ScanPacer();
    _healthWatchdog = MeshHealthWatchdog();
    final generation = ++_runGeneration;
    MeshTransportCoordinator? coordinator;
    IOSink? metricSink;
    try {
      if (kDebugMode) await UniversalBle.setLogLevel(BleLogLevel.debug);
      final siteFingerprint = MeshGatt.siteFingerprint(
        configuration.siteId,
        namespace: configuration.namespace,
      );
      _localToken = _randomNonZero32();

      final documentsDir = await getApplicationDocumentsDirectory();
      final metricFile = File('${documentsDir.path}/mesh-metrics.ndjson');
      metricSink = metricFile.openWrite(mode: FileMode.append);
      _metricSink = metricSink;
      _jsonMetricSink = JsonLineMetricSink(metricSink);

      final siteKeyBytes = await DeviceKeyStore.getOrCreateSiteKey(
        configuration.siteId,
        SiteKeyProvisioning.demoKey(configuration.siteId),
      );
      final relay = MeshRelayEngine(
        siteId: configuration.siteId,
        crypto: AeadEnvelope(siteKeyBytes),
        store: FileRelayStore(Directory('${documentsDir.path}/mesh-relay')),
        clockMs: () => DateTime.now().millisecondsSinceEpoch,
      );
      final server = MeshGattServer(
        onDiagnostic: (kind, peerId, {detail, value}) {
          _reportMetrics([
            RelayMetric(kind, peerId: peerId, detail: detail, value: value),
          ]);
        },
      );
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

      _discoveryMetadata = DiscoveryMetadata(
        fingerprint: siteFingerprint,
        connectionToken: _localToken,
        capabilities: capabilityRelay | capabilityVoice,
      );
      var advertisingActive = false;
      try {
        await MeshAdvertiser.start(_discoveryMetadata!);
        _reportMetrics(const [
          RelayMetric('advertising_started'),
          RelayMetric('advertising_verified'),
        ]);
        advertisingActive = true;
      } catch (error) {
        // Advertising failure is non-fatal. The phone can still scan, connect
        // as a GATT client, receive, and relay traffic. The liveness timer and
        // health watchdog will retry advertising every 30 s via
        // _reassertAdvertising, which now falls back to _desiredMetadata so
        // the first-ever start can be retried after a slow/failing BLE stack.
        _reportMetrics([
          RelayMetric('advertising_failed', detail: error.toString()),
          const RelayMetric('advertising_degraded'),
        ]);
      }
      if (_stopRequested) throw StateError('mesh start cancelled');
      _advertisingLivenessTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_reassertAdvertising()),
      );

      _looping = true;
      _scanCancel = Completer<void>();
      _scanFuture = _scanLoop(siteFingerprint, coordinator, generation);
      unawaited(_scanFuture!);
      onMeshStatus?.call(advertisingActive ? 'advertising' : 'scan_only');
    } catch (_) {
      _looping = false;
      _advertisingLivenessTimer?.cancel();
      _advertisingLivenessTimer = null;
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
    int generation,
  ) async {
    while (_looping) {
      if (_scanPacer.isThrottled) {
        final deferredIdle = _scanPacer.nextIdleDuration();
        _reportMetrics([
          RelayMetric(
            'scan_throttle_deferred',
            value: deferredIdle.inMilliseconds,
          ),
          RelayMetric(
            'scan_duty_cycle',
            value: 0,
            detail: 'throttled; idle=${deferredIdle.inMilliseconds}ms',
          ),
        ]);
        onMeshStatus?.call('idle');
        if (!await _waitOrStop(deferredIdle)) return;
        continue;
      }
      MeshScanReport report;
      final scanWindow = _scanPacer.nextScanWindow();
      try {
        onMeshStatus?.call('scanning');
        _scanPacer.recordScanStart();
        report = await MeshScanner.scanReport(
          window: scanWindow,
          expectedFingerprint: siteFingerprint,
          cancel: _scanCancel?.future,
          onSosAlert: _onCompactSosAlert,
        );
      } catch (error) {
        _reportMetrics([RelayMetric('scan_failed', detail: error.toString())]);
        if (!_looping) return;
        if (!await _waitOrStop(const Duration(seconds: 2))) return;
        continue;
      }
      if (!_looping) return;
      _scanPacer.recordCycleResult(
        devicesSeen: report.devicesSeen,
        peerExpected:
            report.serviceMatches > 0 ||
            coordinator.peerCount > 0 ||
            _connectingPeerIds.isNotEmpty,
      );
      final peers = report.peers;
      _reportMetrics([
        RelayMetric('scan_devices_seen', value: report.devicesSeen),
        RelayMetric('scan_service_matches', value: report.serviceMatches),
        RelayMetric(
          'scan_manufacturer_matches',
          value: report.manufacturerMatches,
        ),
        RelayMetric('scan_malformed_metadata', value: report.malformedMetadata),
        RelayMetric(
          'scan_fingerprint_mismatches',
          value: report.fingerprintMismatches,
        ),
        RelayMetric('scan_peers_accepted', value: peers.length),
        RelayMetric(
          'scan_uuid_only_candidates',
          value: report.uuidOnlyDeviceIds.length,
        ),
        for (final peer in peers)
          RelayMetric(
            'peer_discovered',
            peerId: peer.device.deviceId,
            value: peer.device.rssi,
          ),
        for (final peer in peers)
          RelayMetric(
            'scan_found',
            peerId: peer.device.deviceId,
            value: peer.device.rssi,
          ),
      ]);
      final healthAction = _healthWatchdog.recordCycle(
        devicesSeen: report.devicesSeen,
        connectedPeerCount: coordinator.peerCount,
      );
      switch (healthAction) {
        case MeshHealthAction.none:
          break;
        case MeshHealthAction.reassertAdvertising:
          _reportMetrics([
            RelayMetric(
              'mesh_health_action',
              detail: 'reassertAdvertising',
              value: _healthWatchdog.consecutiveUnhealthyCycles,
            ),
          ]);
          unawaited(_reassertAdvertising());
        case MeshHealthAction.restartController:
          _reportMetrics([
            RelayMetric(
              'mesh_health_action',
              detail: 'restartController',
              value: _healthWatchdog.consecutiveUnhealthyCycles,
            ),
          ]);
          // Scheduled outside this cycle's synchronous continuation: stop()
          // awaits this same scan loop's future, so calling it inline here
          // would deadlock the loop against its own teardown.
          scheduleMicrotask(() => _restartAfterHealthCheckFailure(generation));
          return;
      }
      final candidates = <DiscoveredPeer>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      final capacity =
          MeshTransportCoordinator.maxPeerConnections -
          coordinator.peerCount -
          _connectingPeerIds.length;
      final seenThisCycle = <String>{};
      for (final peer in peers) {
        seenThisCycle.add(peer.device.deviceId);
        if (coordinator.hasPeer(peer.device.deviceId)) {
          _waitingForRemoteDialSinceMs.remove(peer.device.deviceId);
          continue;
        }
        final weShouldInitiate = shouldInitiate(
          _localToken,
          peer.metadata.connectionToken,
        );
        int? waitingSince;
        if (weShouldInitiate) {
          _waitingForRemoteDialSinceMs.remove(peer.device.deviceId);
        } else {
          waitingSince = _waitingForRemoteDialSinceMs.putIfAbsent(
            peer.device.deviceId,
            () => now,
          );
        }
        final dialNow = shouldDialNow(
          localToken: _localToken,
          remoteToken: peer.metadata.connectionToken,
          waitingSinceMs: waitingSince,
          nowMs: now,
          fallbackDelay: _fallbackDialDelay,
        );
        if (!dialNow) continue;
        if (!weShouldInitiate) {
          _reportMetrics([
            RelayMetric(
              'fallback_dial_after_wait',
              peerId: peer.device.deviceId,
            ),
          ]);
        }
        if (candidates.length >= capacity) {
          break;
        }
        if (capacity <= 0) break;
        if (_connectingPeerIds.contains(peer.device.deviceId) ||
            (_retryAfterMs[peer.device.deviceId] ?? 0) > now) {
          continue;
        }
        candidates.add(peer);
      }
      _waitingForRemoteDialSinceMs.removeWhere(
        (deviceId, _) => !seenThisCycle.contains(deviceId),
      );
      for (final peer in candidates) {
        _startConnection(peer, coordinator);
      }
      _processUuidOnlyFallback(report, coordinator, now);
      if (!_looping) return;
      final beacons = report.beacons;
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
      if (!_looping) return;
      try {
        await coordinator.tick();
      } catch (_) {
        // A transient peer failure must not terminate the long-running scan.
      }
      final idleWindow = _scanPacer.nextIdleDuration();
      _reportMetrics([
        RelayMetric(
          'scan_duty_cycle',
          value: _scanPacer.dutyCyclePercent(idleWindow: idleWindow),
          detail:
              'scan=${scanWindow.inMilliseconds}ms '
              'idle=${idleWindow.inMilliseconds}ms',
        ),
      ]);
      onMeshStatus?.call('idle');
      if (!await _waitOrStop(idleWindow)) return;
    }
  }

  /// Terminal recovery action for [MeshHealthAction.restartController]
  /// (Bible audit Task 9): a full stop/start cycle when reasserting
  /// advertising alone has not recovered discovery. This is the same
  /// operation the user currently performs manually by toggling Event Mode
  /// off and back on — automating it is the point of the watchdog.
  Future<void> _restartAfterHealthCheckFailure(int generation) async {
    if (!_looping || generation != _runGeneration) return;
    _reportMetrics(const [RelayMetric('mesh_health_restart_begin')]);
    await stop();
    if (generation != _runGeneration) return;
    try {
      await start();
    } catch (error) {
      _reportMetrics([
        RelayMetric('mesh_health_restart_failed', detail: '$error'),
      ]);
    }
  }

  Future<void> _reassertAdvertising() async {
    if (!_looping) return;
    try {
      await MeshAdvertiser.reassert();
      _reportMetrics(const [
        RelayMetric('advertising_reasserted'),
        RelayMetric('advertising_verified'),
      ]);
    } catch (error) {
      _reportMetrics([
        RelayMetric('advertising_reassert_failed', detail: error.toString()),
        RelayMetric('advertising_failed', detail: error.toString()),
      ]);
    }
  }

  /// Fallback for OEM BLE stacks that fail to deliver the scan-response
  /// packet carrying [DiscoveryMetadata] (Bible audit Task 4): a device
  /// seen matching the MeshSetu service UUID for
  /// [_uuidOnlyFallbackThreshold] consecutive cycles, with no discovery
  /// record, becomes a connection candidate anyway. No fingerprint is
  /// available pre-connect here, so the attempt attaches as unverified and
  /// relies entirely on the post-connection HELLO handshake (Task 5) to
  /// establish or reject site identity — this must never bypass that check.
  void _processUuidOnlyFallback(
    MeshScanReport report,
    MeshTransportCoordinator coordinator,
    int now,
  ) {
    final seenThisCycle = report.uuidOnlyDeviceIds.toSet();
    _uuidOnlySightings.removeWhere((id, _) => !seenThisCycle.contains(id));
    for (final deviceId in seenThisCycle) {
      _uuidOnlySightings[deviceId] = (_uuidOnlySightings[deviceId] ?? 0) + 1;
    }
    if (seenThisCycle.isEmpty) return;

    final capacity =
        MeshTransportCoordinator.maxPeerConnections -
        coordinator.peerCount -
        _connectingPeerIds.length;
    if (capacity <= 0) return;

    var started = 0;
    for (final deviceId in seenThisCycle) {
      if (started >= capacity) break;
      if ((_uuidOnlySightings[deviceId] ?? 0) < _uuidOnlyFallbackThreshold) {
        continue;
      }
      if (coordinator.hasPeer(deviceId) ||
          _connectingPeerIds.contains(deviceId) ||
          (_retryAfterMs[deviceId] ?? 0) > now) {
        continue;
      }
      _reportMetrics([
        RelayMetric('uuid_only_fallback_connect', peerId: deviceId),
      ]);
      _startUuidOnlyConnection(deviceId, coordinator);
      started++;
    }
  }

  Future<void> _connectUuidOnlyPeer(
    String deviceId,
    MeshTransportCoordinator coordinator,
  ) async {
    GattPeerSession? session;
    try {
      session = GattPeerSession.open(
        deviceId,
        onLifecycle: (kind, {phase, detail, value}) {
          _reportMetrics([
            RelayMetric(
              kind,
              peerId: deviceId,
              detail: detail ?? phase,
              value: value,
            ),
          ]);
        },
      );
      await session.awaitReady().timeout(const Duration(seconds: 45));
      if (!_looping) {
        await session.close();
        return;
      }
      // siteFingerprint is unknown pre-connect for a UUID-only fallback
      // peer; 0 marks it unverified until HELLO (Task 5) confirms or
      // rejects the site.
      coordinator.attach(
        deviceId,
        GattPeerSessionLink(session),
        siteFingerprint: 0,
      );
      _retryAfterMs.remove(deviceId);
      _uuidOnlySightings.remove(deviceId);
    } catch (error) {
      _retryAfterMs[deviceId] = DateTime.now().millisecondsSinceEpoch + 10000;
      _reportMetrics([
        RelayMetric(
          'uuid_only_fallback_connect_failed',
          peerId: deviceId,
          detail: session == null
              ? 'open: ${error.toString()}'
              : '${session.phase}: ${session.failure ?? error}',
        ),
      ]);
      unawaited(session?.close());
    }
  }

  void _startUuidOnlyConnection(
    String deviceId,
    MeshTransportCoordinator coordinator,
  ) {
    if (!_connectingPeerIds.add(deviceId)) return;
    final future = _connectUuidOnlyPeer(deviceId, coordinator);
    _connectionAttempts.add(future);
    unawaited(
      future.then(
        (_) {
          _connectionAttempts.remove(future);
          _connectingPeerIds.remove(deviceId);
        },
        onError: (Object _, StackTrace __) {
          _connectionAttempts.remove(future);
          _connectingPeerIds.remove(deviceId);
        },
      ),
    );
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
      session = GattPeerSession.open(
        peer.device.deviceId,
        onLifecycle: (kind, {phase, detail, value}) {
          _reportMetrics([
            RelayMetric(
              kind,
              peerId: peer.device.deviceId,
              detail: detail ?? phase,
              value: value,
            ),
          ]);
        },
      );
      // GattPeerSession has phase-specific timeouts. This outer timeout is
      // only a final guard against a platform implementation that never
      // returns from an operation at all.
      await session.awaitReady().timeout(const Duration(seconds: 45));
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
    } catch (error) {
      _retryAfterMs[peer.device.deviceId] =
          DateTime.now().millisecondsSinceEpoch + 10000;
      _reportMetrics([
        RelayMetric(
          'peer_connect_failed',
          peerId: peer.device.deviceId,
          detail: session == null
              ? 'open: ${error.toString()}'
              : '${session.phase}: ${session.failure ?? error}',
        ),
      ]);
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

  Future<MeshEnvelope?> sendTestObject() async {
    for (var attempt = 0; attempt < 100 && _coordinator == null; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final coordinator = _coordinator;
    if (coordinator == null) return null;

    unawaited(broadcastCompactSos(isTest: true));

    final now = DateTime.now().millisecondsSinceEpoch;
    final envelope = MeshEnvelope(
      objectId: _randomNonZero64(),
      eventId: _randomUuidV4(),
      siteId: configuration.siteId,
      roomId: 'public',
      createdAtMs: now,
      expiresAtMs: now + 60000,
      hopCount: 0,
      hopLimit: 4,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: TestSosPacket.payload,
      originEphemeralId: _localToken,
    );
    await coordinator.send(envelope);
    return envelope;
  }

  /// Sends an immediately detectable emergency alert independently of GATT.
  /// Rich SOS data remains in the normal durable GATT envelope.
  Future<void> broadcastCompactSos({
    bool isTest = false,
    SosEmergencyType emergencyType = SosEmergencyType.general,
    int? originId,
    int? sequence,
    String? reporterUidHex,
  }) async {
    final metadata = _discoveryMetadata;
    if (!_looping || metadata == null) {
      throw StateError('event mode is not running');
    }
    final alert = MeshSosAdvertisement(
      siteFingerprint: metadata.fingerprint,
      originId: originId ?? _localToken,
      sequence: sequence ?? ++_sosSequence,
      flags: MeshSosAdvertisement.flagsFor(emergencyType, isTest: isTest),
      ttl: 4,
      reporterUidHex: isTest
          ? ''
          : MeshSosAdvertisement.normalizeReporterUid(reporterUidHex),
    );
    _reportMetrics([RelayMetric('sos_alert_broadcast', value: alert.sequence)]);
    try {
      await MeshAdvertiser.broadcastSos(alert, metadata);
    } catch (error) {
      _reportMetrics([RelayMetric('sos_alert_failed', detail: '$error')]);
    }
  }

  void _onCompactSosAlert(MeshSosAdvertisement alert, String deviceId) {
    final isOwnAlert = alert.originId == (_localToken & 0xffffffff);
    final now = DateTime.now().millisecondsSinceEpoch;
    _seenCompactAlerts.removeWhere((_, expiresAt) => expiresAt <= now);
    final isDuplicate = _seenCompactAlerts.containsKey(alert.dedupeKey);
    if (isOwnAlert || isDuplicate) return;
    _seenCompactAlerts[alert.dedupeKey] =
        now + const Duration(minutes: 5).inMilliseconds;
    _reportMetrics([
      RelayMetric(
        'sos_alert_received',
        peerId: deviceId,
        value: alert.sequence,
        detail: alert.isTest ? 'test' : 'emergency',
      ),
    ]);
    onCompactSosAlert?.call(alert);
    if (alert.ttl > 1) unawaited(_relayCompactSos(alert));
  }

  Future<void> _relayCompactSos(MeshSosAdvertisement alert) async {
    final metadata = _discoveryMetadata;
    if (!_looping || metadata == null) return;
    final relayed = alert.withTtl(alert.ttl - 1);
    _reportMetrics([
      RelayMetric(
        'sos_alert_relayed',
        value: relayed.sequence,
        detail: 'ttl ${relayed.ttl}',
      ),
    ]);
    try {
      await MeshAdvertiser.broadcastSos(relayed, metadata);
    } catch (error) {
      _reportMetrics([RelayMetric('sos_alert_failed', detail: '$error')]);
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
    _looping = false;
    _advertisingLivenessTimer?.cancel();
    _advertisingLivenessTimer = null;
    if (!(_scanCancel?.isCompleted ?? true)) {
      _scanCancel!.complete();
    }
    final scanFuture = _scanFuture;
    _scanCancel = null;
    _scanFuture = null;
    _retryAfterMs.clear();
    _seenCompactAlerts.clear();
    _uuidOnlySightings.clear();
    _waitingForRemoteDialSinceMs.clear();
    _discoveryMetadata = null;
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
      final connectionAttempts = _connectionAttempts.toList();
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
          detail: metric.detail ?? metric.objectId?.toString(),
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
