import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/mesh_radio_preflight.dart';
import 'package:permission_handler/permission_handler.dart';

const _sdk34Permissions = [
  Permission.bluetoothScan,
  Permission.bluetoothAdvertise,
  Permission.bluetoothConnect,
  Permission.locationWhenInUse,
  Permission.notification,
];

void main() {
  test('reports bluetoothUnavailable before checking permissions', () {
    final result = MeshRadioPreflight.evaluate(
      bluetoothUnavailableMessage: 'Bluetooth is turned off.',
      requiredPermissions: _sdk34Permissions,
      grantedStatuses: {for (final p in _sdk34Permissions) p: false},
      locationServicesOn: false,
    );

    expect(result, isA<MeshRadioBlocked>());
    expect(
      (result as MeshRadioBlocked).reason,
      MeshRadioBlockedReason.bluetoothUnavailable,
    );
  });

  test('reports permissionMissing when any required permission is denied', () {
    final result = MeshRadioPreflight.evaluate(
      bluetoothUnavailableMessage: null,
      requiredPermissions: _sdk34Permissions,
      grantedStatuses: {
        for (final p in _sdk34Permissions) p: true,
        Permission.bluetoothScan: false,
      },
      locationServicesOn: true,
    );

    expect(result, isA<MeshRadioBlocked>());
    expect(
      (result as MeshRadioBlocked).reason,
      MeshRadioBlockedReason.permissionMissing,
    );
  });

  test(
    'reports locationServicesOff when the Location toggle is disabled despite granted permission',
    () {
      final result = MeshRadioPreflight.evaluate(
        bluetoothUnavailableMessage: null,
        requiredPermissions: _sdk34Permissions,
        grantedStatuses: {for (final p in _sdk34Permissions) p: true},
        locationServicesOn: false,
      );

      expect(result, isA<MeshRadioBlocked>());
      expect(
        (result as MeshRadioBlocked).reason,
        MeshRadioBlockedReason.locationServicesOff,
      );
      expect((result).message, contains('Location'));
    },
  );

  test('reports ready when every gate passes', () {
    final result = MeshRadioPreflight.evaluate(
      bluetoothUnavailableMessage: null,
      requiredPermissions: _sdk34Permissions,
      grantedStatuses: {for (final p in _sdk34Permissions) p: true},
      locationServicesOn: true,
    );

    expect(result, isA<MeshRadioReady>());
  });

  test(
    'pre-Android 12 (no location permission required) ignores the Location toggle',
    () {
      final result = MeshRadioPreflight.evaluate(
        bluetoothUnavailableMessage: null,
        requiredPermissions: const [],
        grantedStatuses: const {},
        locationServicesOn: false,
      );

      expect(result, isA<MeshRadioReady>());
    },
  );
}
