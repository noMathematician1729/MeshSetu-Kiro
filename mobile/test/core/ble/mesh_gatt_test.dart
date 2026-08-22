import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:meshsetu_mobile/core/ble/mesh_gatt.dart';
import 'package:meshsetu_mobile/core/ble/ble_discovery.dart';

class _AdvertisingPeripheral extends UniversalBlePeripheralUnsupported {
  PeripheralPlatformConfig? config;
  ManufacturerData? manufacturerData;
  int startCount = 0;
  int stopCount = 0;
  bool reportAdvertising = true;
  PeripheralAdvertisingState state = PeripheralAdvertisingState.idle;

  @override
  Future<PeripheralAdvertisingState> getAdvertisingState() async => state;

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  }) async {
    startCount++;
    if (reportAdvertising) state = PeripheralAdvertisingState.advertising;
    config = platformConfig;
    this.manufacturerData = manufacturerData;
  }

  @override
  Future<void> stopAdvertising() async {
    stopCount++;
    state = PeripheralAdvertisingState.idle;
  }
}

void main() {
  test('MeshSetu service declares the required RX/TX roles', () {
    final service = MeshGatt.buildService();
    final rx = service.characteristics.firstWhere(
      (characteristic) => characteristic.uuid == MeshGatt.rx,
    );
    final tx = service.characteristics.firstWhere(
      (characteristic) => characteristic.uuid == MeshGatt.tx,
    );

    expect(rx.properties, contains(CharacteristicProperty.write));
    expect(tx.properties, contains(CharacteristicProperty.notify));
    // universal_ble adds the CCCD in its Android native service conversion.
    expect(MeshGatt.cccd, '00002902-0000-1000-8000-00805f9b34fb');
  });

  test('beacon metadata round trips bounded UTF-8 anchor IDs', () {
    final encoded = const BeaconMetadata('gate-east').encode();
    expect(BeaconMetadata.decode(encoded)?.anchorId, 'gate-east');
  });

  test('beacon metadata rejects malformed and oversized payloads', () {
    expect(BeaconMetadata.decode(Uint8List.fromList([1, 0xFF])), isNull);
    expect(() => BeaconMetadata('x' * 25).encode(), throwsArgumentError);
  });

  test('manufacturer payloads use one company ID and explicit types', () {
    final encoded = MeshGatt.manufacturerPayload(
      MeshGatt.sosPayloadType,
      Uint8List.fromList([7, 8]),
    );

    expect(encoded, orderedEquals([MeshGatt.sosPayloadType, 7, 8]));
    expect(
      MeshGatt.payloadForType(encoded, MeshGatt.sosPayloadType),
      orderedEquals([7, 8]),
    );
    expect(
      MeshGatt.payloadForType(encoded, MeshGatt.beaconPayloadType),
      isNull,
    );
    expect(MeshGatt.isProductionCompanyId(0), isTrue);
    expect(MeshGatt.isProductionCompanyId(0xFFFE), isTrue);
    expect(MeshGatt.isProductionCompanyId(0xFFFF), isFalse);
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
      expect(peripheral.manufacturerData?.companyId, MeshGatt.manufacturerId);
      expect(
        peripheral.manufacturerData?.payload.first,
        MeshGatt.discoveryPayloadType,
      );
    },
  );

  test('no-op advertising is rejected by state verification', () async {
    final peripheral = _AdvertisingPeripheral()..reportAdvertising = false;
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );
    await MeshAdvertiser.stop();

    expect(
      () => MeshAdvertiser.start(
        const DiscoveryMetadata(
          fingerprint: 1,
          connectionToken: 2,
          capabilities: 1,
        ),
      ),
      throwsStateError,
    );
    expect(MeshAdvertiser.isIntendedToAdvertise, isFalse);
  });

  test(
    'isIntendedToAdvertise reflects start/stop and reassert re-issues advertising',
    () async {
      final peripheral = _AdvertisingPeripheral();
      UniversalBlePeripheral.setInstance(peripheral);
      addTearDown(
        () => UniversalBlePeripheral.setInstance(
          UniversalBlePeripheralUnsupported(),
        ),
      );
      // MeshAdvertiser holds process-wide static state shared with earlier
      // tests in this file; reset explicitly rather than assuming an
      // initial value.
      await MeshAdvertiser.stop();
      expect(MeshAdvertiser.isIntendedToAdvertise, isFalse);

      const metadata = DiscoveryMetadata(
        fingerprint: 1,
        connectionToken: 2,
        capabilities: 1,
      );
      await MeshAdvertiser.start(metadata);
      expect(MeshAdvertiser.isIntendedToAdvertise, isTrue);
      final startCountAfterFirstStart = peripheral.startCount;
      expect(startCountAfterFirstStart, greaterThanOrEqualTo(1));

      await MeshAdvertiser.reassert();
      expect(peripheral.startCount, startCountAfterFirstStart + 1);
      expect(MeshAdvertiser.isIntendedToAdvertise, isTrue);

      final stopCountBeforeFinalStop = peripheral.stopCount;
      await MeshAdvertiser.stop();
      expect(MeshAdvertiser.isIntendedToAdvertise, isFalse);
      expect(peripheral.stopCount, stopCountBeforeFinalStop + 1);

      // reassert after stop must not silently revive advertising.
      final startCountAfterStop = peripheral.startCount;
      await MeshAdvertiser.reassert();
      expect(peripheral.startCount, startCountAfterStop);
      expect(MeshAdvertiser.isIntendedToAdvertise, isFalse);
    },
  );

  group('shouldDialNow', () {
    test('dials immediately when winning the deterministic tie-break', () {
      final result = shouldDialNow(
        localToken: 1,
        remoteToken: 2,
        waitingSinceMs: null,
        nowMs: 0,
      );
      expect(result, isTrue);
    });

    test(
      'does not dial when losing the tie-break before the fallback delay',
      () {
        final result = shouldDialNow(
          localToken: 2,
          remoteToken: 1,
          waitingSinceMs: 1000,
          nowMs: 1000 + const Duration(seconds: 5).inMilliseconds,
          fallbackDelay: const Duration(seconds: 15),
        );
        expect(result, isFalse);
      },
    );

    test('falls back to dialing once the wait meets the fallback delay', () {
      final result = shouldDialNow(
        localToken: 2,
        remoteToken: 1,
        waitingSinceMs: 1000,
        nowMs: 1000 + const Duration(seconds: 15).inMilliseconds,
        fallbackDelay: const Duration(seconds: 15),
      );
      expect(result, isTrue);
    });

    test('never falls back if no wait-start time has been recorded yet', () {
      final result = shouldDialNow(
        localToken: 2,
        remoteToken: 1,
        waitingSinceMs: null,
        nowMs: 1000000,
      );
      expect(result, isFalse);
    });
  });
}
