import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/event_mode_screen.dart';
import 'app/notification_router.dart';
import 'app/sos_incident_navigator.dart';
import 'core/ble/mesh_gatt.dart';
import 'core/ble/permission_gate.dart';
import 'feature/onboarding/onboarding_screen.dart';
import 'feature/rooms/rooms_screen.dart';
import 'feature/sos/incident_detail_screen.dart';

/// Port of `in.meshsetu.app.MainActivity` (Kotlin `app/` module) — the
/// runnable shell. The foreground task owns BLE discovery, relay transport,
/// metrics, and the small diagnostic bridge displayed by the event screen.
/// `ProviderScope` binds the Dev B repositories (Bible §4.2) that live in
/// this UI isolate — `core/data`, `feature/join`, `feature/rooms`,
/// `feature/sos`, `feature/voice`, `feature/gateway`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MeshGatt.validateCompanyId();
  FlutterForegroundTask.initCommunicationPort();
  unawaited(NotificationRouter.configure(FlutterLocalNotificationsPlugin()));
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationRouter.flushPending();
      SosIncidentNavigator.openPending();
    });
    final eventMode = enforcePermissions
        ? const PermissionGate(child: EventModeScreen())
        : const EventModeScreen();
    return MaterialApp(
      title: 'MeshSetu',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      navigatorKey: navigatorKey,
      home: enforceOnboarding ? OnboardingGate(child: eventMode) : eventMode,
      onGenerateRoute: (settings) {
        if (settings.arguments is! Map) return null;
        final args = (settings.arguments as Map).cast<String, Object?>();

        if (settings.name == '/rooms') {
          final roomId = args['roomId'] as String?;
          if (roomId == null || roomId.isEmpty) return null;
          return MaterialPageRoute(
            builder: (_) => RoomsScreen(initialRoomId: roomId),
          );
        }

        if (settings.name == '/incident') {
          final siteId = args['siteId'] as String?;
          final eventId = args['eventId'] as String?;
          final objectId = args['objectId'] as int?;
          if (siteId == null || eventId == null || objectId == null) {
            return null;
          }
          return MaterialPageRoute(
            builder: (_) => IncidentDetailScreen(
              siteId: siteId,
              eventId: eventId,
              objectId: objectId,
            ),
          );
        }

        return null;
      },
    );
  }
}
