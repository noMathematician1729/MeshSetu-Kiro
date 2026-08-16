import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/ble_permissions.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('Android 31 requests BLE and RSSI location permissions', () {
    expect(BlePermissions.runtimePermissions(sdkInt: 31), [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ]);
  });

  test('Android 33+ also requests notification permission', () {
    expect(BlePermissions.runtimePermissions(sdkInt: 33), [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.notification,
    ]);
  });

  test('pre-Android 12 falls back to location permission only', () {
    expect(BlePermissions.runtimePermissions(sdkInt: 30), [
      Permission.locationWhenInUse,
    ]);
  });

  test('Bluetooth availability gets an actionable message', () {
    expect(
      BlePermissions.availabilityMessageFor(AvailabilityState.poweredOn),
      isNull,
    );
    expect(
      BlePermissions.availabilityMessageFor(AvailabilityState.poweredOff),
      contains('turned off'),
    );
    expect(
      BlePermissions.availabilityMessageFor(AvailabilityState.unsupported),
      contains('does not support'),
    );
    expect(
      BlePermissions.availabilityMessageFor(AvailabilityState.unauthorized),
      contains('permission'),
    );
  });
}
