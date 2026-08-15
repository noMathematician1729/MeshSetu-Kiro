import 'package:universal_ble/universal_ble.dart';

import 'mesh_gatt.dart';

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
/// - `scan` is a plain time-bounded `Future`, not a cancellable coroutine
///   (matches the Bible's own §7.4 reference implementation); a caller
///   needing early cancellation would need to layer that on separately.
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
  }) async {
    final found = <String, DiscoveredPeer>{};
    final subscription = UniversalBle.scanStream.listen((device) {
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
    await Future<void>.delayed(window);
    await UniversalBle.stopScan();
    await subscription.cancel();
    return found.values.toList(growable: false);
  }
}
