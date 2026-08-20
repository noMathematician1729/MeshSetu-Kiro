import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/event_mode_screen.dart';
import 'app/sos_alert_notifications.dart';
import 'app/sos_incident_navigator.dart';
import 'app/notification_router.dart';
import 'core/ble/permission_gate.dart';
import 'feature/onboarding/onboarding_screen.dart';
import 'feature/sos/incident_detail_screen.dart';

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
  unawaited(NotificationRouter.configure(FlutterLocalNotificationsPlugin()));
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => NotificationRouter.flushPending(),
    );
    final eventMode = widget.enforcePermissions
        ? const PermissionGate(child: EventModeScreen())
        : const EventModeScreen();
    return MaterialApp(
      title: 'MeshSetu',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      navigatorKey: navigatorKey,
      home: widget.enforceOnboarding
          ? OnboardingGate(child: eventMode)
          : eventMode,
      onGenerateRoute: (settings) {
        if (settings.name != '/incident' || settings.arguments is! Map) {
          return null;
        }
        final args = (settings.arguments as Map).cast<String, Object?>();
        final siteId = args['siteId'] as String?;
        final eventId = args['eventId'] as String?;
        final objectId = args['objectId'] as int?;
        if (siteId == null || eventId == null || objectId == null) return null;
        return MaterialPageRoute(
          builder: (_) => IncidentDetailScreen(
            siteId: siteId,
            eventId: eventId,
            objectId: objectId,
          ),
        );
      },
    );
  }
}
