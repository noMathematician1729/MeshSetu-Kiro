import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/event_mode_screen.dart';
import 'app/sos_alert_notifications.dart';
import 'app/sos_incident_navigator.dart';
import 'core/ble/permission_gate.dart';
import 'feature/onboarding/onboarding_screen.dart';

/// Port of `in.meshsetu.app.MainActivity` (Kotlin `app/` module) — the
/// runnable shell. The foreground task owns BLE discovery, relay transport,
/// metrics, and the small diagnostic bridge displayed by the event screen.
/// `ProviderScope` binds the Dev B repositories (Bible §4.2) that live in
/// this UI isolate — `core/data`, `feature/join`, `feature/rooms`,
/// `feature/sos`, `feature/voice`, `feature/gateway`.
void main() {
  // The notification plugin uses platform channels, so the binding must exist
  // before it is initialized; otherwise the tap handler is never registered
  // and every SOS tap falls back to the launcher activity's home screen.
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ProviderScope(child: MeshSetuApp()));
  // Notification payloads are MeshSetu routes, never external web links.
  unawaited(
    SosAlertNotifications.ensureInitialized(
      onTapPayload: SosIncidentNavigator.openPayload,
    ),
  );
}

class MeshSetuApp extends StatefulWidget {
  const MeshSetuApp({
    super.key,
    this.enforcePermissions = true,
    this.enforceOnboarding = true,
  });

  /// Test-only escape hatches. Production construction requires both the
  /// persisted emergency profile and runtime BLE permissions.
  final bool enforcePermissions;
  final bool enforceOnboarding;

  @override
  State<MeshSetuApp> createState() => _MeshSetuAppState();
}

class _MeshSetuAppState extends State<MeshSetuApp> {
  @override
  void initState() {
    super.initState();
    // A notification tap can cold-start the app before the navigator exists.
    // Deliver it as soon as the first frame has mounted one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SosIncidentNavigator.openPending();
    });
  }

  @override
  Widget build(BuildContext context) {
    final eventMode = widget.enforcePermissions
        ? const PermissionGate(child: EventModeScreen())
        : const EventModeScreen();
    return MaterialApp(
      navigatorKey: SosIncidentNavigator.key,
      title: 'MeshSetu',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: widget.enforceOnboarding
          ? OnboardingGate(child: eventMode)
          : eventMode,
    );
  }
}
