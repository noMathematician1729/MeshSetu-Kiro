import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:meshsetu_mobile/core/ble/mesh_gatt.dart';
import 'package:meshsetu_mobile/core/ble/ble_discovery.dart';

class _AdvertisingPeripheral extends UniversalBlePeripheralUnsupported {
  PeripheralPlatformConfig? config;

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  }) async {
    config = platformConfig;
  }
}

void main() {
  test('beacon metadata round trips bounded UTF-8 anchor IDs', () {
    final encoded = const BeaconMetadata('gate-east').encode();
    expect(BeaconMetadata.decode(encoded)?.anchorId, 'gate-east');
  });

  test('beacon metadata rejects malformed and oversized payloads', () {
    expect(BeaconMetadata.decode(Uint8List.fromList([1, 0xFF])), isNull);
    expect(() => BeaconMetadata('x' * 25).encode(), throwsArgumentError);
  });

  test(
    'advertising moves discovery metadata to Android scan response',
    () async {
      final peripheral = _AdvertisingPeripheral();
      UniversalBlePeripheral.setInstance(peripheral);
      addTearDown(
        () => UniversalBlePeripheral.setInstance(
          UniversalBlePeripheralUnsupported(),
        ),
      );

      await MeshAdvertiser.start(
        const DiscoveryMetadata(
          fingerprint: 1,
          connectionToken: 2,
          capabilities: 1,
        ),
      );
      expect(
        peripheral.config?.android?.addManufacturerDataInScanResponse,
        isTrue,
      );
      expect(peripheral.config?.android?.addServicesInScanResponse, isNull);
    },
  );
}
