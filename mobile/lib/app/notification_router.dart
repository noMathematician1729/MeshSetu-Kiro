import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'debug_runtime_log.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class NotificationRouter {
  NotificationRouter._();
  static String? _pendingPayload;

  static String incidentPayload({
    required String siteId,
    required String eventId,
    required int objectId,
  }) =>
      jsonEncode({'siteId': siteId, 'eventId': eventId, 'objectId': objectId});

  static Future<void> configure(FlutterLocalNotificationsPlugin plugin) async {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        // #region agent log
        DebugRuntimeLog.write(
          hypothesisId: 'H2',
          location: 'notification_router.dart:onDidReceiveNotificationResponse',
          message: 'Notification tap received by router',
          data: {'hasPayload': payload != null && payload.isNotEmpty},
        );
        // #endregion
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
        // #region agent log
        DebugRuntimeLog.write(
          hypothesisId: 'H2',
          location: 'notification_router.dart:open',
          message: 'Incident route deferred until navigator is ready',
          data: {'hasRequiredFields': _hasIncidentFields(data)},
        );
        // #endregion
        _pendingPayload = payload;
        return;
      }
      // #region agent log
      DebugRuntimeLog.write(
        hypothesisId: 'H2',
        location: 'notification_router.dart:open',
        message: 'Navigating from rich SOS notification to incident',
        data: {'hasRequiredFields': _hasIncidentFields(data)},
      );
      // #endregion
      navigator.pushNamed('/incident', arguments: data);
    } catch (error) {
      // #region agent log
      DebugRuntimeLog.write(
        hypothesisId: 'H2',
        location: 'notification_router.dart:open',
        message: 'Notification payload could not be routed',
        data: {'error': '$error'},
      );
      // #endregion
      // Invalid/stale notification payloads should not prevent app launch.
    }
  }

  static bool _hasIncidentFields(Map<String, Object?> data) =>
      data['siteId'] is String &&
      data['eventId'] is String &&
      data['objectId'] is int;

  static void flushPending() {
    final payload = _pendingPayload;
    _pendingPayload = null;
    if (payload != null) open(payload);
  }
}
