import 'package:permission_handler/permission_handler.dart';

import 'ble_permissions.dart';

/// Distinct, machine-readable reasons the mesh radio is not usable right
/// now. Every reason maps to a specific remediation the user can act on —
/// unlike a bare bool, this lets the scan loop and the room UI agree on
/// *why* discovery is blocked instead of both guessing "no peers yet".
enum MeshRadioBlockedReason {
  /// Bluetooth adapter is off, unsupported, or in a transitional state.
  bluetoothUnavailable,

  /// One or more required runtime permissions (scan/advertise/connect,
  /// location) have not been granted.
  permissionMissing,

  /// Android's system Location toggle is off. BLE scanning on most Android
  /// builds returns zero results with permission granted and Bluetooth on
  /// if this OS-level toggle is off — this is checked separately from the
  /// `Permission.locationWhenInUse` grant.
  locationServicesOff,
}

/// Result of one [MeshRadioPreflight.check] call. Sealed so call sites must
/// handle every blocked reason explicitly rather than falling through to a
/// generic "not ready" message.
sealed class MeshRadioPreflightResult {
  const MeshRadioPreflightResult();
}

final class MeshRadioReady extends MeshRadioPreflightResult {
  const MeshRadioReady();
}

final class MeshRadioBlocked extends MeshRadioPreflightResult {
  const MeshRadioBlocked(this.reason, this.message);

  final MeshRadioBlockedReason reason;
  final String message;
}

/// Checks every precondition the mesh radio needs before scanning or
/// advertising can produce results, and is cheap enough to call once per
/// scan cycle (Bible audit Task 1/Task 3) rather than only once at Event
/// Mode startup. A permission granted at startup does not guarantee the OS
/// Location toggle stays on, and this gate is the single place that notices
/// when it doesn't.
abstract final class MeshRadioPreflight {
  static Future<MeshRadioPreflightResult> check({required int sdkInt}) async {
    final bluetoothMessage = await BlePermissions.availabilityMessage();
    final required = BlePermissions.runtimePermissions(sdkInt: sdkInt);
    final grantedStatuses = <Permission, bool>{
      for (final permission in required)
        permission: (await permission.status).isGranted,
    };
    final locationServicesOn = required.contains(Permission.locationWhenInUse)
        ? await Permission.location.serviceStatus == ServiceStatus.enabled
        : true;

    return evaluate(
      bluetoothUnavailableMessage: bluetoothMessage,
      requiredPermissions: required,
      grantedStatuses: grantedStatuses,
      locationServicesOn: locationServicesOn,
    );
  }

  /// Pure decision logic, separated from the platform-channel calls in
  /// [check] so it is directly unit-testable without mocking
  /// `permission_handler`/`universal_ble` platform channels (matching how
  /// `BlePermissions.availabilityMessageFor` is split from
  /// `availabilityMessage`).
  static MeshRadioPreflightResult evaluate({
    required String? bluetoothUnavailableMessage,
    required List<Permission> requiredPermissions,
    required Map<Permission, bool> grantedStatuses,
    required bool locationServicesOn,
  }) {
    if (bluetoothUnavailableMessage != null) {
      return MeshRadioBlocked(
        MeshRadioBlockedReason.bluetoothUnavailable,
        bluetoothUnavailableMessage,
      );
    }

    for (final permission in requiredPermissions) {
      if (grantedStatuses[permission] != true) {
        return const MeshRadioBlocked(
          MeshRadioBlockedReason.permissionMissing,
          'Nearby devices / location permission is required. '
          'Allow it in Settings, then try again.',
        );
      }
    }

    if (requiredPermissions.contains(Permission.locationWhenInUse) &&
        !locationServicesOn) {
      return const MeshRadioBlocked(
        MeshRadioBlockedReason.locationServicesOff,
        'Turn on Location in Settings to scan for nearby devices. '
        'Android blocks Bluetooth scanning while Location is off, even '
        'with permission granted.',
      );
    }

    return const MeshRadioReady();
  }
}
