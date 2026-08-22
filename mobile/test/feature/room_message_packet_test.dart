import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/device_key_store.dart';
import 'package:meshsetu_mobile/feature/rooms/room_message_packet.dart';
import 'package:meshsetu_mobile/feature/rooms/room_presence.dart';

void main() {
  group('RoomMessagePacketCodec v2', () {
    test('round-trips text and sender name', () {
      final packet = RoomMessagePacketCodec.encode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        text: 'hello mesh',
        senderName: 'Alice',
      );

      final content = RoomMessagePacketCodec.decode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        packet: packet,
      );
      expect(content.text, 'hello mesh');
      expect(content.senderName, 'Alice');
    });

    test('round-trips with null sender name stored as empty string', () {
      final packet = RoomMessagePacketCodec.encode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        text: 'no name',
      );

      final content = RoomMessagePacketCodec.decode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        packet: packet,
      );
      expect(content.text, 'no name');
      expect(content.senderName, '');
    });

    test('truncates a sender name longer than 64 UTF-8 bytes without splitting runes', () {
      // 'ñ' is 2 bytes in UTF-8. 35 repetitions = 70 bytes, which exceeds 64.
      final longName = 'ñ' * 35;
      final packet = RoomMessagePacketCodec.encode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        text: 'hi',
        senderName: longName,
      );
      final content = RoomMessagePacketCodec.decode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        packet: packet,
      );
      expect(content.text, 'hi');
      // The decoded name must be a valid string within the byte limit.
      final bytes = utf8.encode(content.senderName!);
      expect(bytes.length, lessThanOrEqualTo(RoomMessagePacketCodec.maxSenderNameBytes));
      // Must not have been cut mid-rune (valid UTF-8 round-trips cleanly).
      expect(utf8.decode(bytes), content.senderName);
    });

    test('rejects tampering in the sender-name region', () {
      final packet = RoomMessagePacketCodec.encode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        text: 'original',
        senderName: 'Alice',
      );
      // Flip a byte inside the name region (byte 8 = first name char for v2).
      final tampered = Uint8List.fromList(packet)..[8] ^= 0xFF;

      expect(
        () => RoomMessagePacketCodec.decode(
          siteId: 'demo-site',
          roomId: 'public',
          eventId: 'event-1',
          packet: tampered,
        ),
        throwsFormatException,
      );
    });

    test('rejects context swap (wrong roomId)', () {
      final packet = RoomMessagePacketCodec.encode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        text: 'original',
        senderName: 'Alice',
      );
      expect(
        () => RoomMessagePacketCodec.decode(
          siteId: 'demo-site',
          roomId: 'medical',
          eventId: 'event-1',
          packet: packet,
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown version byte', () {
      final packet = RoomMessagePacketCodec.encode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        text: 'hi',
        senderName: 'Bob',
      );
      // Clobber version byte (index 4) to an unknown value.
      final badVersion = Uint8List.fromList(packet)..[4] = 99;
      expect(
        () => RoomMessagePacketCodec.decode(
          siteId: 'demo-site',
          roomId: 'public',
          eventId: 'event-1',
          packet: badVersion,
        ),
        throwsFormatException,
      );
    });
  });

  group('RoomMessagePacketCodec v1 back-compat', () {
    test('decodes a legacy v1 packet with null senderName', () {
      final v1Packet = _buildV1Packet(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        text: 'v1 message',
      );
      final content = RoomMessagePacketCodec.decode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        packet: v1Packet,
      );
      expect(content.text, 'v1 message');
      expect(content.senderName, isNull);
    });

    test('rejects tampering in a v1 packet', () {
      final v1Packet = _buildV1Packet(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        text: 'original',
      );
      final tampered = Uint8List.fromList(v1Packet)..[8] ^= 1;
      expect(
        () => RoomMessagePacketCodec.decode(
          siteId: 'demo-site',
          roomId: 'public',
          eventId: 'event-1',
          packet: tampered,
        ),
        throwsFormatException,
      );
    });
  });

  group('room presence round-trip', () {
    test('lobby member list round-trips', () {
      final packet = RoomPresenceCodec.encode(
        const RoomMember(
          memberId: 'member-1',
          displayName: 'Asha',
          joinedAtMs: 42,
        ),
      );

      final member = RoomPresenceCodec.decode(packet);
      expect(member?.memberId, 'member-1');
      expect(member?.displayName, 'Asha');
      expect(member?.joinedAtMs, 42);
    });
  });
}

// ---------------------------------------------------------------------------
// Helper: hand-craft a v1 packet using the same key derivation the codec uses
// so back-compat tests are not sensitive to the encode implementation.
// ---------------------------------------------------------------------------

Uint8List _buildV1Packet({
  required String siteId,
  required String roomId,
  required String eventId,
  required String text,
}) {
  const magic = [0x4D, 0x53, 0x52, 0x4D]; // "MSRM"
  const version = 1;
  const headerBytes = 7;
  const tagBytes = 16;

  final textBytes = Uint8List.fromList(utf8.encode(text.trim()));
  final header = Uint8List(headerBytes + textBytes.length);
  header.setRange(0, magic.length, magic);
  header[4] = version;
  ByteData.sublistView(header).setUint16(5, textBytes.length, Endian.big);
  header.setRange(headerBytes, header.length, textBytes);

  final key = SiteKeyProvisioning.demoKey(siteId);
  final context = utf8.encode('$siteId\u0000$roomId\u0000$eventId\u0000');
  final authenticated = Uint8List.fromList([...context, ...header]);
  final digest = Hmac(sha256, key).convert(authenticated);
  final tag = Uint8List.fromList(digest.bytes.sublist(0, tagBytes));
  return Uint8List.fromList([...header, ...tag]);
}
