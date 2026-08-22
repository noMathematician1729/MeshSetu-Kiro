import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import 'mesh_gatt.dart';
import 'sos_advertisement.dart';
import 'async_lock.dart';
import '../model/model.dart';

/// Port of `in.meshsetu.ble.MeshAdvertiser` / `MeshScanner` (Kotlin
/// `BleDiscovery.kt`).
///
/// Deviations from the Kotlin source:
/// - `universal_ble`'s `startAdvertising` doesn't expose raw BLE
///   service-data (only `services`, `localName`, `manufacturerData`), so
///   [DiscoveryMetadata] rides as typed manufacturer data instead. This
///   turned out to match what the
///   Kotlin source independently switched to as well (upstream hit the same
///   31-byte legacy advertising-response budget problem).
/// - `scan` is time-bounded but also accepts a cancellation future so a
///   foreground service can release the radio immediately on shutdown.
abstract final class MeshAdvertiser {
  static final AsyncLock _advertisingLock = AsyncLock();
  static int _advertisingGeneration = 0;
  static DiscoveryMetadata? _activeMetadata;

  /// The metadata this advertiser has been asked to broadcast, set on every
  /// [start] call regardless of whether the platform confirms advertising.
  /// [reassert] uses this so it can retry after an initial failed [start],
  /// not just after a previously verified session.
  static DiscoveryMetadata? _desiredMetadata;

  /// True once [start] has been called with metadata (intent), even if the
  /// platform has not yet confirmed [PeripheralAdvertisingState.advertising].
  /// [reassert] can attempt a first-time start when this is true and
  /// [_activeMetadata] is still null.
  static bool get isIntendedToAdvertise =>
      _activeMetadata != null || _desiredMetadata != null;

  static Future<void> start(DiscoveryMetadata metadata) async {
    _desiredMetadata = metadata;
    final previousMetadata = _activeMetadata;
    _advertisingGeneration++;
    try {
      await UniversalBlePeripheral.startAdvertising(
        services: const [MeshGatt.service],
        localName: 'MeshSetu',
        manufacturerData: ManufacturerData(
          MeshGatt.manufacturerId,
          MeshGatt.manufacturerPayload(
            MeshGatt.discoveryPayloadType,
            metadata.encode(),
          ),
        ),
        // Keep the 128-bit service UUID in the primary advertisement for the
        // scan filter and move the 14-byte discovery record to the scan
        // response so both packets stay within Android's 31-byte limit.
        platformConfig: PeripheralPlatformConfig(
          android: PeripheralAndroidOptions(
            addManufacturerDataInScanResponse: true,
          ),
        ),
      );
      final state = await _waitForAdvertising();
      if (state != PeripheralAdvertisingState.advertising) {
        throw StateError('platform advertising state is ${state.name}');
      }
      _activeMetadata = metadata;
    } catch (error) {
      // A failed reassert should leave the last-known metadata available for
      // a later watchdog retry; an initial failed start remains inactive.
      _activeMetadata = previousMetadata;
      throw StateError('BLE advertising verification failed: $error');
    }
  }

  static Future<PeripheralAdvertisingState> _waitForAdvertising() async {
    // 60 attempts × 50 ms = 3 seconds. OEM BLE stacks (especially on first
    // use after boot) can take 1–2 s to initialise the peripheral role; the
    // original 1-second window was too tight and caused spurious failures.
    for (var attempt = 0; attempt < 60; attempt++) {
      final state = await UniversalBlePeripheral.getAdvertisingState();
      if (state == PeripheralAdvertisingState.advertising ||
          state == PeripheralAdvertisingState.error) {
        return state;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return UniversalBlePeripheral.getAdvertisingState();
  }

  /// Re-issues [start] with the last-known or desired discovery metadata.
  /// Uses [_activeMetadata] (previously verified) when available, otherwise
  /// falls back to [_desiredMetadata] so the first-ever start can be retried
  /// after an initial failure. Native Android rejects a second start while
  /// the previous advertiser is active, so the reassert path explicitly
  /// reaches idle before starting again.
  /// A no-op if neither [_activeMetadata] nor [_desiredMetadata] is set
  /// (i.e. [start] has never been called, or [stop] has been called).
  static Future<void> reassert() async {
    final metadata = _activeMetadata ?? _desiredMetadata;
    if (metadata == null) return;
    await UniversalBlePeripheral.stopAdvertising();
    await _waitForIdle();
    await start(metadata);
  }

  static Future<void> _waitForIdle() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final state = await UniversalBlePeripheral.getAdvertisingState();
      if (state == PeripheralAdvertisingState.idle) return;
      if (state == PeripheralAdvertisingState.error) {
        throw StateError('platform advertising state is error while stopping');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final state = await UniversalBlePeripheral.getAdvertisingState();
    if (state != PeripheralAdvertisingState.idle) {
      throw StateError('platform advertising did not stop before reassert');
    }
  }

  static Future<void> stop() async {
    _advertisingGeneration++;
    _activeMetadata = null;
    _desiredMetadata = null;
    await UniversalBlePeripheral.stopAdvertising();
  }

  /// Temporarily replaces discovery metadata with a continuously repeated SOS
  /// advertisement. Android broadcasts the active advertisement repeatedly;
  /// the normal discovery beacon is restored after the bounded alert window.
  static Future<void> broadcastSos(
    MeshSosAdvertisement alert,
    DiscoveryMetadata discovery, {
    Duration duration = const Duration(seconds: 2),
  }) => _advertisingLock.synchronized(() async {
    final generation = ++_advertisingGeneration;
    await UniversalBlePeripheral.stopAdvertising();
    try {
      await UniversalBlePeripheral.startAdvertising(
        services: const [MeshGatt.service],
        localName: 'MeshSetu',
        manufacturerData: ManufacturerData(
          MeshGatt.manufacturerId,
          MeshGatt.manufacturerPayload(MeshGatt.sosPayloadType, alert.encode()),
        ),
        platformConfig: PeripheralPlatformConfig(
          android: PeripheralAndroidOptions(
            addManufacturerDataInScanResponse: true,
          ),
        ),
      );
      await Future<void>.delayed(duration);
    } finally {
      // Do not revive the advertiser after event mode explicitly stopped.
      if (generation == _advertisingGeneration) {
        await UniversalBlePeripheral.stopAdvertising();
        await start(discovery);
      }
    }
  });
}

class DiscoveredPeer {
  const DiscoveredPeer({required this.device, required this.metadata});

  final BleDevice device;
  final DiscoveryMetadata metadata;
}

class MeshScanReport {
  const MeshScanReport({
    required this.peers,
    required this.beacons,
    required this.devicesSeen,
    required this.serviceMatches,
    required this.manufacturerMatches,
    required this.malformedMetadata,
    required this.fingerprintMismatches,
    this.uuidOnlyDeviceIds = const [],
  });

  final List<DiscoveredPeer> peers;
  final List<BeaconObservation> beacons;
  final int devicesSeen;
  final int serviceMatches;
  final int manufacturerMatches;
  final int malformedMetadata;
  final int fingerprintMismatches;

  /// Device IDs that matched the MeshSetu service UUID but never produced a
  /// decodable discovery record during this scan window (Bible audit
  /// Task 4). Some OEM BLE stacks fail to deliver or merge the scan-response
  /// packet that carries [DiscoveryMetadata], so `serviceMatches > 0` while
  /// `manufacturerMatches == 0` for that device — normal discovery then
  /// finds zero peers with no fallback. [MeshEventController] uses this list
  /// as a last-resort connection candidate set after repeated blind cycles,
  /// relying on the post-connection HELLO handshake (not this scan) to
  /// establish site identity, since no fingerprint is available here.
  final List<String> uuidOnlyDeviceIds;
}

abstract final class MeshScanner {
  static Future<List<DiscoveredPeer>> scan({
    Duration window = const Duration(seconds: 4),
    int? expectedFingerprint,
    Future<void>? cancel,
  }) async => (await scanReport(
    window: window,
    expectedFingerprint: expectedFingerprint,
    cancel: cancel,
  )).peers;

  static Future<MeshScanReport> scanReport({
    Duration window = const Duration(seconds: 4),
    int? expectedFingerprint,
    Future<void>? cancel,
    void Function(MeshSosAdvertisement alert, String deviceId)? onSosAlert,
  }) async {
    final found = <String, DiscoveredPeer>{};
    final devicesSeen = <String>{};
    final serviceMatches = <String>{};
    final manufacturerMatches = <String>{};
    final malformedMetadata = <String>{};
    final fingerprintMismatches = <String>{};
    final discoveryRecordSeen = <String>{};
    final beacons = <String, BeaconObservation>{};
    StreamSubscription<BleDevice>? subscription;
    var started = false;
    try {
      subscription = UniversalBle.scanStream.listen((device) {
        devicesSeen.add(device.deviceId);
        if (device.services.any(
          (service) => service.toLowerCase() == MeshGatt.service,
        )) {
          serviceMatches.add(device.deviceId);
        }
        for (final data in device.manufacturerDataList) {
          if (data.companyId != MeshGatt.manufacturerId) continue;
          final sosPayload = MeshGatt.payloadForType(
            data.payload,
            MeshGatt.sosPayloadType,
          );
          if (sosPayload != null) {
            final alert = MeshSosAdvertisement.decode(sosPayload);
            if (alert != null &&
                (expectedFingerprint == null ||
                    alert.siteFingerprint ==
                        (expectedFingerprint & 0xffffffff))) {
              onSosAlert?.call(alert, device.deviceId);
            }
            continue;
          }
          final beaconPayload = MeshGatt.payloadForType(
            data.payload,
            MeshGatt.beaconPayloadType,
          );
          if (beaconPayload != null) {
            final metadata = BeaconMetadata.decode(beaconPayload);
            if (metadata != null) {
              final observation = BeaconObservation(
                anchorId: metadata.anchorId,
                rssi: device.rssi ?? -128,
                observedAtMs: DateTime.now().millisecondsSinceEpoch,
              );
              final previous = beacons[metadata.anchorId];
              if (previous == null || observation.rssi > previous.rssi) {
                beacons[metadata.anchorId] = observation;
              }
            }
            continue;
          }
          final discoveryPayload = MeshGatt.payloadForType(
            data.payload,
            MeshGatt.discoveryPayloadType,
          );
          if (discoveryPayload == null) continue;
          manufacturerMatches.add(device.deviceId);
          discoveryRecordSeen.add(device.deviceId);
          final metadata = DiscoveryMetadata.decode(discoveryPayload);
          if (metadata == null) {
            malformedMetadata.add(device.deviceId);
            continue;
          }
          if (expectedFingerprint != null &&
              metadata.fingerprint != expectedFingerprint) {
            fingerprintMismatches.add(device.deviceId);
            continue;
          }
          found[device.deviceId] = DiscoveredPeer(
            device: device,
            metadata: metadata,
          );
        }
      });
      await UniversalBle.startScan(
        // Some Android devices expose the service UUID and manufacturer data
        // in different advertisement/scan-response packets. A native service
        // filter can discard the device before Dart receives the packet that
        // contains our discovery metadata, so filtering is done above.
        scanFilter: ScanFilter(),
        platformConfig: PlatformConfig(
          android: AndroidOptions(scanMode: AndroidScanMode.lowLatency),
        ),
      );
      started = true;
      final timeout = Future<void>.delayed(window);
      if (cancel == null) {
        await timeout;
      } else {
        await Future.any<void>([timeout, cancel]);
      }
    } finally {
      if (started) {
        try {
          await UniversalBle.stopScan();
        } catch (_) {
          // Preserve the original scan failure while still releasing the
          // subscription below.
        }
      }
      await subscription?.cancel();
    }
    return MeshScanReport(
      peers: found.values.toList(growable: false),
      beacons: beacons.values.toList(growable: false),
      devicesSeen: devicesSeen.length,
      serviceMatches: serviceMatches.length,
      manufacturerMatches: manufacturerMatches.length,
      malformedMetadata: malformedMetadata.length,
      fingerprintMismatches: fingerprintMismatches.length,
      uuidOnlyDeviceIds: serviceMatches
          .difference(discoveryRecordSeen)
          .toList(growable: false),
    );
  }
}

abstract final class MeshBeaconScanner {
  static Future<List<BeaconObservation>> scan({
    Duration window = const Duration(seconds: 2),
    Future<void>? cancel,
  }) async {
    final found = <String, BeaconObservation>{};
    StreamSubscription<BleDevice>? subscription;
    var started = false;
    try {
      subscription = UniversalBle.scanStream.listen((device) {
        for (final data in device.manufacturerDataList) {
          if (data.companyId != MeshGatt.manufacturerId) continue;
          final payload = MeshGatt.payloadForType(
            data.payload,
            MeshGatt.beaconPayloadType,
          );
          if (payload == null) continue;
          final metadata = BeaconMetadata.decode(payload);
          if (metadata == null) continue;
          final observation = BeaconObservation(
            anchorId: metadata.anchorId,
            rssi: device.rssi ?? -128,
            observedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          final previous = found[metadata.anchorId];
          if (previous == null || observation.rssi > previous.rssi) {
            found[metadata.anchorId] = observation;
          }
        }
      });
      await UniversalBle.startScan(
        scanFilter: ScanFilter(),
        platformConfig: PlatformConfig(
          android: AndroidOptions(scanMode: AndroidScanMode.lowLatency),
        ),
      );
      started = true;
      final timeout = Future<void>.delayed(window);
      await (cancel == null ? timeout : Future.any<void>([timeout, cancel]));
    } finally {
      if (started) {
        try {
          await UniversalBle.stopScan();
        } catch (_) {
          // Preserve the original scan failure while releasing the stream.
        }
      }
      await subscription?.cancel();
    }
    return found.values.toList(growable: false);
  }
}
