import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/model/model.dart';
import '../feature/rooms/room_message_packet.dart';

/// Returned by [roomMessageAlertFor] when a received mesh object should raise
/// a system notification. Carries everything [RoomMessageNotifications.show]
/// needs without that function having to touch raw envelope bytes.
class RoomMessageAlert {
  const RoomMessageAlert({
    required this.senderName,
    required this.text,
    required this.siteId,
    required this.roomId,
    required this.eventId,
    required this.objectId,
  });

  /// Display name from the v2 packet, or an empty string for v1 legacy
  /// packets (the notification title falls back to a generic label).
  final String senderName;
  final String text;
  final String siteId;
  final String roomId;
  final String eventId;
  final int objectId;
}

/// Pure decision function: decides whether [received] should raise a
/// system notification and, if so, what the notification should say.
///
/// Returns null — suppress — when:
/// - The payload type is not [PayloadType.roomMessage].
/// - [localEphemeralId] matches the envelope's [originEphemeralId]: the
///   sender's own device should never see a notification for its own message.
/// - [activeRoomId] matches the envelope's [roomId]: the user has that
///   room open and is already reading the message.
/// - The packet HMAC fails, the packet is too short, or decoding throws for
///   any other reason (tampered or foreign packets must never surface).
///
/// Extracted as a free function so it can be unit-tested without the
/// foreground-service plugin or a real Android device.
RoomMessageAlert? roomMessageAlertFor({
  required ReceivedObject received,
  required int? localEphemeralId,
  required String? activeRoomId,
}) {
  if (received.envelope.payloadType != PayloadType.roomMessage) return null;
  // Never notify about a message this device originated.
  if (localEphemeralId != null &&
      received.envelope.originEphemeralId == localEphemeralId) {
    return null;
  }
  // Suppress while the recipient is looking at the room chat screen.
  if (activeRoomId != null && received.envelope.roomId == activeRoomId) {
    return null;
  }
  try {
    final content = RoomMessagePacketCodec.decode(
      siteId: received.envelope.siteId,
      roomId: received.envelope.roomId,
      eventId: received.envelope.eventId,
      packet: received.envelope.payload,
    );
    return RoomMessageAlert(
      senderName: content.senderName ?? '',
      text: content.text,
      siteId: received.envelope.siteId,
      roomId: received.envelope.roomId,
      eventId: received.envelope.eventId,
      objectId: received.envelope.objectId,
    );
  } catch (_) {
    // Unauthenticated, tampered, or malformed packets are silently dropped.
    return null;
  }
}

/// System-notification presenter for incoming BLE room messages.
///
/// Uses a dedicated Android channel (`meshsetu-room-messages-v1`) at
/// [Importance.high] / [Priority.high] so room chat never shares importance
/// with SOS alerts — a user who mutes chat must never inadvertently mute
/// emergency alarms. Channel importance is immutable after first creation
/// on Android, so the two channels are deliberately kept separate.
abstract final class RoomMessageNotifications {
  static const String channelId = 'meshsetu-room-messages-v1';
  static const String _channelName = 'Room messages';
  static const String _channelDescription =
      'Offline BLE mesh room chat messages';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static void Function(String? payload)? _onTapPayload;

  /// Stable notification id so the durable-inbox relay replay replaces an
  /// existing card rather than stacking a duplicate for the same message.
  static int idForKey(String eventId) {
    final id = ('room:$eventId').hashCode & 0x7fffffff;
    return id == 0 ? 1 : id;
  }

  /// Initialises the plugin, optionally registering the tap handler.
  /// Safe to call from the foreground task isolate (no BuildContext needed).
  static Future<void> ensureInitialized({
    void Function(String? payload)? onTapPayload,
  }) async {
    if (onTapPayload != null) _onTapPayload = onTapPayload;
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) =>
          _onTapPayload?.call(response.payload),
    );
    _initialized = true;
  }

  /// Shows a room-message notification. [payload] is the tap destination
  /// encoded by [roomPayload].
  static Future<void> show({
    required RoomMessageAlert alert,
    required String? payload,
  }) async {
    try {
      await ensureInitialized();
      final title = alert.senderName.isNotEmpty
          ? alert.senderName
          : 'New room message';
      final body = alert.text;
      await _plugin.show(
        id: idForKey(alert.eventId),
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: AndroidNotificationCategory.message,
            // Private: hide message text on the lock screen to protect
            // potentially sensitive field-operation communications.
            visibility: NotificationVisibility.private,
          ),
        ),
      );
    } catch (_) {
      // A notification failure must never stop BLE relaying.
    }
  }

  /// Encodes the tap-routing payload for a room notification.
  static String roomPayload({
    required String siteId,
    required String roomId,
  }) =>
      jsonEncode({'type': 'room', 'siteId': siteId, 'roomId': roomId});
}
