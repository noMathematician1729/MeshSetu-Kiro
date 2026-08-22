import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/app/room_message_notifications.dart';
import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/feature/rooms/room_message_packet.dart';

void main() {
  final now = DateTime.now().millisecondsSinceEpoch;

  /// Builds a minimal [ReceivedObject] for a room message.
  ReceivedObject makeReceived({
    required String siteId,
    required String roomId,
    required String eventId,
    required int objectId,
    required int originEphemeralId,
    required Uint8List payload,
  }) =>
      ReceivedObject(
        envelope: MeshEnvelope(
          objectId: objectId,
          eventId: eventId,
          siteId: siteId,
          roomId: roomId,
          createdAtMs: now,
          expiresAtMs: now + 3600000,
          hopCount: 1,
          hopLimit: 5,
          priority: PriorityBand.p2Normal,
          payloadType: PayloadType.roomMessage,
          payload: payload,
          originEphemeralId: originEphemeralId,
        ),
        peerId: 'peer-a',
        receivedAtMs: now,
      );

  Uint8List validPayload({
    required String siteId,
    required String roomId,
    required String eventId,
    String text = 'hello',
    String senderName = 'Alice',
  }) =>
      RoomMessagePacketCodec.encode(
        siteId: siteId,
        roomId: roomId,
        eventId: eventId,
        text: text,
        senderName: senderName,
      );

  group('roomMessageAlertFor', () {
    test('returns alert for a valid foreign message', () {
      final payload = validPayload(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-1',
      );
      final received = makeReceived(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-1',
        objectId: 1,
        originEphemeralId: 9999,
        payload: payload,
      );

      final alert = roomMessageAlertFor(
        received: received,
        localEphemeralId: 1234,
        activeRoomId: null,
      );

      expect(alert, isNotNull);
      expect(alert!.senderName, 'Alice');
      expect(alert.text, 'hello');
      expect(alert.roomId, 'public');
    });

    test('suppresses when originEphemeralId matches local device', () {
      final payload = validPayload(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-2',
      );
      final received = makeReceived(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-2',
        objectId: 2,
        originEphemeralId: 1234,
        payload: payload,
      );

      final alert = roomMessageAlertFor(
        received: received,
        localEphemeralId: 1234,
        activeRoomId: null,
      );

      expect(alert, isNull);
    });

    test('suppresses when activeRoomId matches the message room', () {
      final payload = validPayload(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-3',
      );
      final received = makeReceived(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-3',
        objectId: 3,
        originEphemeralId: 9999,
        payload: payload,
      );

      final alert = roomMessageAlertFor(
        received: received,
        localEphemeralId: 1234,
        activeRoomId: 'public',
      );

      expect(alert, isNull);
    });

    test('does not suppress when activeRoomId is a different room', () {
      final payload = validPayload(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-4',
      );
      final received = makeReceived(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-4',
        objectId: 4,
        originEphemeralId: 9999,
        payload: payload,
      );

      final alert = roomMessageAlertFor(
        received: received,
        localEphemeralId: 1234,
        activeRoomId: 'medical',
      );

      expect(alert, isNotNull);
    });

    test('suppresses a tampered/unauthenticated packet', () {
      final payload = validPayload(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-5',
      );
      // Corrupt the HMAC tag (last 16 bytes).
      final tampered = Uint8List.fromList(payload)
        ..[payload.length - 1] ^= 0xFF;

      final received = makeReceived(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-5',
        objectId: 5,
        originEphemeralId: 9999,
        payload: tampered,
      );

      final alert = roomMessageAlertFor(
        received: received,
        localEphemeralId: 1234,
        activeRoomId: null,
      );

      expect(alert, isNull);
    });

    test('suppresses a non-roomMessage payload type', () {
      final received = ReceivedObject(
        envelope: MeshEnvelope(
          objectId: 6,
          eventId: 'evt-6',
          siteId: 'site-1',
          roomId: 'public',
          createdAtMs: now,
          expiresAtMs: now + 3600000,
          hopCount: 0,
          hopLimit: 5,
          priority: PriorityBand.p2Normal,
          payloadType: PayloadType.structuredSos,
          payload: Uint8List.fromList([1, 2, 3, 4]),
          originEphemeralId: 9999,
        ),
        peerId: 'peer-a',
        receivedAtMs: now,
      );

      final alert = roomMessageAlertFor(
        received: received,
        localEphemeralId: 1234,
        activeRoomId: null,
      );

      expect(alert, isNull);
    });

    test('uses generic title when senderName is empty (v2 with empty name)', () {
      final payload = RoomMessagePacketCodec.encode(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-7',
        text: 'anonymous message',
        senderName: '',
      );
      final received = makeReceived(
        siteId: 'site-1',
        roomId: 'public',
        eventId: 'evt-7',
        objectId: 7,
        originEphemeralId: 9999,
        payload: payload,
      );

      final alert = roomMessageAlertFor(
        received: received,
        localEphemeralId: 1234,
        activeRoomId: null,
      );

      expect(alert, isNotNull);
      // senderName empty — the show() method will fall back to generic title.
      expect(alert!.senderName, '');
      expect(alert.text, 'anonymous message');
    });
  });
}
