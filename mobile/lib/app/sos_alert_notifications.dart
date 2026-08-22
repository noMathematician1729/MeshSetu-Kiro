import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/ble/sos_advertisement.dart';

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
  static void Function(String? payload)? _onTapPayload;

  /// Stable notification id for one logical SOS, so the enriched update
  /// replaces the initial relay alert instead of adding a second card.
  static int idForKey(String key) {
    final id = key.hashCode & 0x7fffffff;
    return id == 0 ? 1 : id;
  }

  /// Initializes the plugin, optionally registering the tap handler.
  ///
  /// Both isolates and several call sites reach this. `show()` calls it
  /// without a handler, so the handler is stored separately and the
  /// dispatcher reads it late: whichever call arrives first, a tap still
  /// routes into the app once [onTapPayload] has been supplied.
  static Future<void> ensureInitialized({
    void Function(String? payload)? onTapPayload,
  }) async {
    if (onTapPayload != null) _onTapPayload = onTapPayload;
    if (_initialized) {
      if (onTapPayload != null) await _replayLaunchPayload();
      return;
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) =>
          _onTapPayload?.call(response.payload),
    );
    _initialized = true;
    if (_onTapPayload != null) await _replayLaunchPayload();
  }

  /// Delivers the payload of a notification that cold-started the app.
  static Future<void> _replayLaunchPayload() async {
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _onTapPayload?.call(launch?.notificationResponse?.payload);
    }
  }

  /// CEAL-style fallback for a compact BLE alert. This can be read and relayed
  /// without internet, while identity, contacts, and precise location remain
  /// encrypted until a control-room lookup succeeds.
  static String compactPacketBody(
    MeshSosAdvertisement alert, {
    required String availability,
  }) {
    final sender = alert.hasReporterUid
        ? 'CEAL ID ${alert.reporterUidHex.toUpperCase()}'
        : 'Anonymous mesh sender';
    final packet =
        '${alert.originId.toRadixString(16).padLeft(8, '0').toUpperCase()}-${alert.sequence.toString().padLeft(5, '0')}';
    final hops = alert.ttl == 1
        ? '1 hop remaining'
        : '${alert.ttl} hops remaining';
    return '⚠️ COMPACT SOS PACKET\n'
        '${alert.emergencyType.label.toUpperCase()}\n'
        '$sender · packet $packet\n'
        'Bluetooth mesh relay · $hops\n'
        '$availability\n'
        'Name, contacts, and precise location are encrypted.';
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
