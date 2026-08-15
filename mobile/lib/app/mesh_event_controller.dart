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

  MeshTransportCoordinator? _coordinator;
  int _localToken = 0;
  IOSink? _metricSink;
  bool _looping = false;
  bool _starting = false;
  bool _stopRequested = false;

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
      final jsonSink = JsonLineMetricSink(metricSink);

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
        onMetrics: (metrics) {
          final now = DateTime.now().millisecondsSinceEpoch;
          for (final metric in metrics) {
            jsonSink.write(
              ProtocolMetric(
                timeMs: now,
                peer: metric.peerId,
                kind: metric.kind,
                value: metric.value,
                detail: metric.objectId?.toString(),
              ),
            );
          }
        },
      );
      await coordinator.start();
      if (_stopRequested) throw StateError('mesh start cancelled');
      _coordinator = coordinator;

      await MeshAdvertiser.start(
        DiscoveryMetadata(
          fingerprint: siteFingerprint,
          connectionToken: _localToken,
          capabilities: capabilityRelay | capabilityVoice,
        ),
      );
      if (_stopRequested) throw StateError('mesh start cancelled');

      _looping = true;
      unawaited(_scanLoop(siteFingerprint, coordinator));
    } catch (_) {
      _looping = false;
      _coordinator = null;
      await coordinator?.stop();
      try {
        await MeshAdvertiser.stop();
      } catch (_) {
        // Advertising may not have started yet.
      }
      await metricSink?.close();
      _metricSink = null;
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
        peers = await MeshScanner.scan(expectedFingerprint: siteFingerprint);
      } catch (_) {
        if (!_looping) return;
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      for (final peer in peers) {
        if (!_looping) return;
        if (!shouldInitiate(_localToken, peer.metadata.connectionToken)) {
          continue;
        }
        if (coordinator.hasPeer(peer.device.deviceId)) continue;
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
        } catch (_) {
          unawaited(session?.close());
        }
      }
      if (!_looping) return;
      try {
        await coordinator.tick();
      } catch (_) {
        // A transient peer failure must not terminate the long-running scan.
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
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
      await coordinator?.stop();
    } finally {
      await metricSink?.close();
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
