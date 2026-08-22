import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'sos_incident_navigator.dart';

final navigatorKey = SosIncidentNavigator.key;

class NotificationRouter {
  NotificationRouter._();
  static String? _pendingPayload;

  static String incidentPayload({
    required String siteId,
    required String eventId,
    required int objectId,
  }) =>
      jsonEncode({'siteId': siteId, 'eventId': eventId, 'objectId': objectId});

  /// Payload that routes a tap to [RoomsScreen] opened on [roomId].
  static String roomPayload({
    required String siteId,
    required String roomId,
  }) =>
      jsonEncode({'type': 'room', 'siteId': siteId, 'roomId': roomId});

  static Future<void> configure(FlutterLocalNotificationsPlugin plugin) async {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        open(payload);
      },
    );
    final details = await plugin.getNotificationAppLaunchDetails();
    {
      final payload = details?.notificationResponse?.payload;
      if (details?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        open(payload);
      }
    }
  }

  static void open(String payload) {
    try {
      final data = (jsonDecode(payload) as Map).cast<String, Object?>();
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        _pendingPayload = payload;
        return;
      }
      // Room-message tap: open the rooms screen with the matching room.
      if (data['type'] == 'room') {
        navigator.pushNamed('/rooms', arguments: data);
        return;
      }
      // SOS incident tap (legacy path — no 'type' key).
      navigator.pushNamed('/incident', arguments: data);
    } catch (_) {
      // Invalid/stale notification payloads should not prevent app launch.
    }
  }

  static void flushPending() {
    final payload = _pendingPayload;
    _pendingPayload = null;
    if (payload != null) open(payload);
  }
}
