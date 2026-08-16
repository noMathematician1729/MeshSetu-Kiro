import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/ble_permissions.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('Android 31 requests bluetooth and location permissions', () {
    expect(BlePermissions.runtimePermissions(sdkInt: 31), [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ]);
  });

  test('Android 33+ also requests the notification permission', () {
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
}
