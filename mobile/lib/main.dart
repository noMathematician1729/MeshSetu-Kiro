import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app/event_mode_screen.dart';
import 'app/sos_alert_notifications.dart';
import 'core/ble/permission_gate.dart';
import 'feature/onboarding/onboarding_screen.dart';

/// Port of `in.meshsetu.app.MainActivity` (Kotlin `app/` module) — the
/// runnable shell. The foreground task owns BLE discovery, relay transport,
/// metrics, and the small diagnostic bridge displayed by the event screen.
/// `ProviderScope` binds the Dev B repositories (Bible §4.2) that live in
/// this UI isolate — `core/data`, `feature/join`, `feature/rooms`,
/// `feature/sos`, `feature/voice`, `feature/gateway`.
void main() {
  FlutterForegroundTask.initCommunicationPort();
  // Tapping an emergency alert opens that SOS's dedicated incident page.
  SosAlertNotifications.ensureInitialized(
    onTapPayload: (payload) {
      final url = (payload ?? '').trim();
      if (url.isEmpty) return;
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) return;
      launchUrl(uri, mode: LaunchMode.externalApplication);
    },
  );
  runApp(const ProviderScope(child: MeshSetuApp()));
}

class MeshSetuApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final eventMode = enforcePermissions
        ? const PermissionGate(child: EventModeScreen())
        : const EventModeScreen();
    return MaterialApp(
      title: 'MeshSetu',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: enforceOnboarding ? OnboardingGate(child: eventMode) : eventMode,
    );
  }
}
