import 'package:permission_handler/permission_handler.dart';

/// Port of `in.meshsetu.ble.BlePermissions` (Kotlin `BlePermissions.kt`).
///
/// `sdkInt` is a required parameter here rather than defaulting to the live
/// `Build.VERSION.SDK_INT` (as the Kotlin default arg does) so this stays
/// unit-testable with no platform channel. The caller (the app shell) is
/// responsible for sourcing the real Android SDK level.
abstract final class BlePermissions {
  static List<Permission> runtimePermissions({required int sdkInt}) {
    if (sdkInt >= 31) {
      return [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        if (sdkInt >= 33) Permission.notification,
      ];
    }
    return const [Permission.locationWhenInUse];
  }

  static Future<Map<Permission, PermissionStatus>> request({
    required int sdkInt,
  }) => runtimePermissions(sdkInt: sdkInt).request();
}
