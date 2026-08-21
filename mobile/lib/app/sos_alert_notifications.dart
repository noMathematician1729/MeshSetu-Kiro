import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shared presentation for emergency alerts.
///
/// Both isolates use this: the foreground BLE task raises the immediate
/// "relaying" alert, and the UI isolate replaces it in place once the
/// control-room backend has returned the decrypted incident detail. Using one
/// deterministic id per SOS keeps a single, updating notification instead of
/// stacking duplicates for every relay hop.
abstract final class SosAlertNotifications {
  static const String channelId = 'meshsetu-sos-alerts-v1';
  static const String _channelName = 'SOS alerts';
  static const String _channelDescription = 'Nearby MeshSetu emergency signals';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Stable notification id for one logical SOS, so the enriched update
  /// replaces the initial relay alert instead of adding a second card.
  static int idForKey(String key) {
    final id = key.hashCode & 0x7fffffff;
    return id == 0 ? 1 : id;
  }

  static Future<void> ensureInitialized({
    void Function(String? payload)? onTapPayload,
  }) async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onTapPayload == null
          ? null
          : (response) => onTapPayload(response.payload),
    );
    _initialized = true;
    if (onTapPayload != null) {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        onTapPayload(launch?.notificationResponse?.payload);
      }
    }
  }

  /// Shows or replaces an emergency alert. [payload] carries the incident
  /// page URL that a tap should open.
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      await ensureInitialized();
      await _plugin.show(
        id: id == 0 ? 1 : id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            ticker: 'SOS received',
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            onlyAlertOnce: false,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } catch (_) {
      // A notification failure must never stop BLE relaying.
    }
  }
}
