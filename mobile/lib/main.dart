import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/event_mode_screen.dart';
import 'core/ble/permission_gate.dart';

/// Port of `in.meshsetu.app.MainActivity` (Kotlin `app/` module) — the
/// runnable shell. The foreground task owns BLE discovery, relay transport,
/// metrics, and the small diagnostic bridge displayed by the event screen.
/// `ProviderScope` binds the Dev B repositories (Bible §4.2) that live in
/// this UI isolate — `core/data`, `feature/join`, `feature/rooms`,
/// `feature/sos`, `feature/voice`, `feature/gateway`.
void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ProviderScope(child: MeshSetuApp()));
}

class MeshSetuApp extends StatelessWidget {
  const MeshSetuApp({super.key, this.enforcePermissions = true});

  /// Test-only escape hatch for the event screen. Production construction
  /// keeps the permission gate enabled.
  final bool enforcePermissions;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshSetu',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: enforcePermissions
          ? const PermissionGate(child: EventModeScreen())
          : const EventModeScreen(),
    );
  }
}
