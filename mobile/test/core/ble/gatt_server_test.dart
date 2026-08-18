import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/gatt_server.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble/src/universal_ble.g.dart' show PeripheralService;

class _DelayedPeripheral extends UniversalBlePeripheralUnsupported {
  PeripheralService? requestedService;

  @override
  Future<void> addService(
    PeripheralService service, {
    bool primary = true,
    Duration? timeout,
  }) async {
    requestedService = service;
  }

  @override
  Future<void> clearServices() async {}

  void completeService([String? error]) {
    final service = requestedService;
    if (service == null) throw StateError('addService was not called');
    updateServiceAdded(BlePeripheralServiceAdded(service.uuid, error));
  }
}

void main() {
  test('server does not complete startup until serviceAdded arrives', () async {
    final peripheral = _DelayedPeripheral();
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );

    final server = MeshGattServer();
    var completed = false;
    final start = server.start().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    peripheral.completeService();
    await start;
    expect(completed, isTrue);
    await server.stop();
  });

  test('service registration failure never reports a ready server', () async {
    final peripheral = _DelayedPeripheral();
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );

    final server = MeshGattServer();
    final start = server.start();
    await Future<void>.delayed(Duration.zero);
    peripheral.completeService('gatt_service_registration_failed');
    await expectLater(start, throwsA(isA<StateError>()));
    await server.stop();
  });
}
