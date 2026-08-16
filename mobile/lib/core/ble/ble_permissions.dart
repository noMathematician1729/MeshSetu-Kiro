import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

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
        // ZoneResolver uses BLE RSSI observations, so this app derives
        // physical proximity from scan results and cannot use neverForLocation.
        Permission.locationWhenInUse,
        if (sdkInt >= 33) Permission.notification,
      ];
    }
    return const [Permission.locationWhenInUse];
  }

  static Future<Map<Permission, PermissionStatus>> request({
    required int sdkInt,
  }) => runtimePermissions(sdkInt: sdkInt).request();

  static Future<String?> availabilityMessage() async {
    try {
      return availabilityMessageFor(
        await UniversalBle.getBluetoothAvailabilityState(),
      );
    } catch (_) {
      return 'Bluetooth status could not be checked. Turn Bluetooth on and try again.';
    }
  }

  static String? availabilityMessageFor(
    AvailabilityState state,
  ) => switch (state) {
    AvailabilityState.poweredOn => null,
    AvailabilityState.poweredOff =>
      'Bluetooth is turned off. Turn on Bluetooth in Settings, then tap Start event mode again.',
    AvailabilityState.unsupported =>
      'This device does not support Bluetooth Low Energy, so MeshSetu cannot relay messages.',
    AvailabilityState.unauthorized =>
      'Bluetooth access is blocked. Allow Nearby devices/Bluetooth permission for MeshSetu in Settings.',
    AvailabilityState.resetting =>
      'Bluetooth is starting or stopping. Wait a moment, then try Start event mode again.',
    AvailabilityState.unknown =>
      'Bluetooth is unavailable right now. Turn Bluetooth on and try again.',
  };
}
