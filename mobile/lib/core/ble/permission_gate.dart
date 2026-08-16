import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_permissions.dart';

/// Blocks the app until the runtime permissions required by the BLE mesh have
/// been granted. This follows CEAL's onboarding model: users can retry or go
/// to Android settings, but cannot enter the event UI with a half-authorized
/// radio.
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key, required this.child});

  final Widget child;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  List<Permission> _required = const [];
  Map<Permission, PermissionStatus> _statuses = const {};
  bool _loading = true;
  bool _requesting = false;
  bool _bluetoothEnabled = true;

  bool get _allGranted {
    if (_loading) return false;
    if (_required.isEmpty) return true;
    return _statuses.length == _required.length &&
        _statuses.values.every((status) => status.isGranted) &&
        _bluetoothEnabled;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_allGranted) {
      unawaited(_refresh());
    }
  }

  Future<void> _load() async {
    // The deployed app is Android-only. Keep widget tests and non-Android
    // tooling usable without trying to invoke Android platform channels.
    if (defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    _required = BlePermissions.runtimePermissions(
      sdkInt: androidInfo.version.sdkInt,
    );
    await _refresh();
    if (mounted && !_allGranted) {
      // Request on first launch as well as from the visible button. If Android
      // has permanently denied one, the screen remains here with Settings.
      await _requestPermissions();
    }
  }

  Future<void> _refresh() async {
    if (_required.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final statuses = <Permission, PermissionStatus>{
      for (final permission in _required) permission: await permission.status,
    };
    var bluetoothEnabled = true;
    if (_required.contains(Permission.bluetoothScan)) {
      bluetoothEnabled =
          await Permission.bluetooth.serviceStatus == ServiceStatus.enabled;
    }
    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _bluetoothEnabled = bluetoothEnabled;
      _loading = false;
    });
  }

  Future<void> _requestPermissions() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      // Ask one permission at a time so the location dialog is not hidden by
      // Android's Bluetooth permission group handling.
      for (final permission in _required) {
        if (!(await permission.status).isGranted) {
          await permission.request();
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  String _label(Permission permission) {
    if (permission == Permission.bluetoothScan) return 'Bluetooth scan';
    if (permission == Permission.bluetoothAdvertise) {
      return 'Bluetooth advertise';
    }
    if (permission == Permission.bluetoothConnect) {
      return 'Bluetooth connection';
    }
    if (permission == Permission.locationWhenInUse) return 'Location';
    if (permission == Permission.notification) return 'Notifications';
    return permission.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_allGranted) return widget.child;
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions required')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.security, size: 64),
                  const SizedBox(height: 20),
                  Text(
                    'MeshSetu needs permission before you can enter the app.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bluetooth and location are required to discover, send, '
                    'and receive mesh messages. Notifications keep the relay '
                    'alive while the app is in the background.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    for (final permission in _required)
                      ListTile(
                        leading: Icon(
                          _statuses[permission]?.isGranted == true
                              ? Icons.check_circle
                              : Icons.cancel_outlined,
                          color: _statuses[permission]?.isGranted == true
                              ? Colors.green
                              : Colors.red,
                        ),
                        title: Text(_label(permission)),
                        dense: true,
                      ),
                    if (!_bluetoothEnabled)
                      const ListTile(
                        leading: Icon(
                          Icons.bluetooth_disabled,
                          color: Colors.red,
                        ),
                        title: Text('Turn Bluetooth on to continue'),
                        dense: true,
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _requesting ? null : _requestPermissions,
                      icon: _requesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.shield_outlined),
                      label: Text(
                        _requesting ? 'Requesting…' : 'Grant permissions',
                      ),
                    ),
                    if (_statuses.values.any(
                      (status) => status.isPermanentlyDenied,
                    ))
                      TextButton(
                        onPressed: openAppSettings,
                        child: const Text('Open Android settings'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
