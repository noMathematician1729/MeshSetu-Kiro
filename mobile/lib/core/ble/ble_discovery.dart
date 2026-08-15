import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import 'mesh_gatt.dart';
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
  static Future<void> start(DiscoveryMetadata metadata) =>
      UniversalBlePeripheral.startAdvertising(
        services: const [MeshGatt.service],
        localName: 'MeshSetu',
        manufacturerData: ManufacturerData(
          MeshGatt.developmentManufacturerId,
          metadata.encode(),
        ),
      );

  static Future<void> stop() => UniversalBlePeripheral.stopAdvertising();
}

class DiscoveredPeer {
  const DiscoveredPeer({required this.device, required this.metadata});

  final BleDevice device;
  final DiscoveryMetadata metadata;
}

abstract final class MeshScanner {
  static Future<List<DiscoveredPeer>> scan({
    Duration window = const Duration(seconds: 4),
    int? expectedFingerprint,
    Future<void>? cancel,
  }) async {
    final found = <String, DiscoveredPeer>{};
    StreamSubscription<BleDevice>? subscription;
    var started = false;
    try {
      subscription = UniversalBle.scanStream.listen((device) {
        for (final data in device.manufacturerDataList) {
          if (data.companyId != MeshGatt.developmentManufacturerId) continue;
          final metadata = DiscoveryMetadata.decode(data.payload);
          if (metadata == null) continue;
          if (expectedFingerprint != null &&
              metadata.fingerprint != expectedFingerprint) {
            continue;
          }
          found[device.deviceId] = DiscoveredPeer(
            device: device,
            metadata: metadata,
          );
        }
      });
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: const [MeshGatt.service]),
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
    return found.values.toList(growable: false);
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
