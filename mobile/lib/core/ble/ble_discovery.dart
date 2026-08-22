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

  /// Whether [start] has been called more recently than [stop] for the
  /// current advertising generation. This tracks *intent*, not a confirmed
  /// platform state — `universal_ble` exposes no query for whether Android
  /// is still actually broadcasting, which is exactly the failure mode this
  /// is meant to catch (Bible audit Task 3): Android can silently stop
  /// advertising (radio toggled, too many concurrent advertisers) while
  /// this flag still reads true. [reassert] is the mitigation.
  static bool get isIntendedToAdvertise => _activeMetadata != null;

  static Future<void> start(DiscoveryMetadata metadata) async {
    _advertisingGeneration++;
    _activeMetadata = metadata;
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
  }

  /// Re-issues [start] with the last-known discovery metadata. Safe to call
  /// periodically as a liveness re-assertion: `startAdvertising` is
  /// idempotent from this app's perspective, and this is the only available
  /// mitigation for Android silently dropping an active advertisement since
  /// there is no platform callback for "advertising stopped unexpectedly".
  /// A no-op if advertising was never started or has since been [stop]ped.
  static Future<void> reassert() async {
    final metadata = _activeMetadata;
    if (metadata == null) return;
    await start(metadata);
  }

  static Future<void> stop() async {
    _advertisingGeneration++;
    _activeMetadata = null;
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
