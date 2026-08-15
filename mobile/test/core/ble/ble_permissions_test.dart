import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/ble_permissions.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('Android 12+ requests granular bluetooth permissions', () {
    expect(BlePermissions.runtimePermissions(sdkInt: 31), [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.microphone,
    ]);
  });

  test('pre-Android 12 falls back to location permission', () {
    expect(BlePermissions.runtimePermissions(sdkInt: 30), [
      Permission.locationWhenInUse,
      Permission.microphone,
    ]);
  });
}
