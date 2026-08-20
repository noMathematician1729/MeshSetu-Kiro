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
///   [DiscoveryMetadata] rides as manufacturer data instead, tagged with
///   [MeshGatt.developmentManufacturerId]. This turned out to match what the
///   Kotlin source independently switched to as well (upstream hit the same
///   31-byte legacy advertising-response budget problem).
/// - `scan` is time-bounded but also accepts a cancellation future so a
///   foreground service can release the radio immediately on shutdown.
abstract final class MeshAdvertiser {
  static final AsyncLock _advertisingLock = AsyncLock();
  static int _advertisingGeneration = 0;

  static Future<void> start(DiscoveryMetadata metadata) async {
    _advertisingGeneration++;
    await UniversalBlePeripheral.startAdvertising(
      services: const [MeshGatt.service],
      localName: 'MeshSetu',
      manufacturerData: ManufacturerData(
        MeshGatt.developmentManufacturerId,
        metadata.encode(),
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

  static Future<void> stop() async {
    _advertisingGeneration++;
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
          MeshGatt.sosManufacturerId,
          alert.encode(),
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
  });

  final List<DiscoveredPeer> peers;
  final List<BeaconObservation> beacons;
  final int devicesSeen;
  final int serviceMatches;
  final int manufacturerMatches;
  final int malformedMetadata;
  final int fingerprintMismatches;
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
          if (data.companyId == MeshGatt.sosManufacturerId) {
            final alert = MeshSosAdvertisement.decode(data.payload);
            if (alert != null &&
                (expectedFingerprint == null ||
                    alert.siteFingerprint ==
                        (expectedFingerprint & 0xffffffff))) {
              onSosAlert?.call(alert, device.deviceId);
            }
            continue;
          }
          if (data.companyId == MeshGatt.beaconManufacturerId) {
            final metadata = BeaconMetadata.decode(data.payload);
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
          if (data.companyId != MeshGatt.developmentManufacturerId) continue;
          manufacturerMatches.add(device.deviceId);
          final metadata = DiscoveryMetadata.decode(data.payload);
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
          if (data.companyId != MeshGatt.beaconManufacturerId) continue;
          final metadata = BeaconMetadata.decode(data.payload);
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
