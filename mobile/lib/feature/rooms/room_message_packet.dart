import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/ble/device_key_store.dart';

/// Authenticated application payload carried inside a mesh envelope.
///
/// CEAL validates its active compact SOS advertisement with CRC8 and includes
/// an HMAC helper for authenticated fragments. Room messages need stronger
/// integrity than CRC, so this format uses a 128-bit truncated HMAC-SHA256 in
/// addition to the transport's AES-GCM authentication.
///
/// Wire layout: `[magic:4][version:1][textLength:2][utf8Text][hmac:16]`.
abstract final class RoomMessagePacketCodec {
  static const List<int> _magic = [0x4D, 0x53, 0x52, 0x4D]; // "MSRM"
  static const int _version = 1;
  static const int _headerBytes = 7;
  static const int _tagBytes = 16;
  static const int maxTextBytes = 4096;

  static Uint8List encode({
    required String siteId,
    required String roomId,
    required String eventId,
    required String text,
  }) {
    final message = text.trim();
    if (siteId.trim().isEmpty ||
        roomId.trim().isEmpty ||
        eventId.trim().isEmpty) {
      throw ArgumentError('site, room, and event ids must not be blank');
    }
    final textBytes = Uint8List.fromList(utf8.encode(message));
    if (textBytes.isEmpty || textBytes.length > maxTextBytes) {
      throw ArgumentError('message must be 1..$maxTextBytes UTF-8 bytes');
    }
    final headerAndText = Uint8List(_headerBytes + textBytes.length);
    headerAndText.setRange(0, _magic.length, _magic);
    headerAndText[_magic.length] = _version;
    ByteData.sublistView(
      headerAndText,
    ).setUint16(5, textBytes.length, Endian.big);
    headerAndText.setRange(_headerBytes, headerAndText.length, textBytes);
    final tag = _tag(
      siteId: siteId,
      roomId: roomId,
      eventId: eventId,
      packetWithoutTag: headerAndText,
    );
    return Uint8List.fromList([...headerAndText, ...tag]);
  }

  static bool isEncoded(Uint8List packet) =>
      packet.length >= _headerBytes + _tagBytes &&
      _constantTimeEquals(
        Uint8List.sublistView(packet, 0, _magic.length),
        Uint8List.fromList(_magic),
      );

  static String decode({
    required String siteId,
    required String roomId,
    required String eventId,
    required Uint8List packet,
  }) {
    if (!isEncoded(packet)) {
      throw const FormatException('not a MeshSetu room-message packet');
    }
    if (packet[4] != _version) {
      throw const FormatException('unsupported room-message packet version');
    }
    final textLength = ByteData.sublistView(packet).getUint16(5, Endian.big);
    final expectedLength = _headerBytes + textLength + _tagBytes;
    if (textLength < 1 ||
        textLength > maxTextBytes ||
        packet.length != expectedLength) {
      throw const FormatException('invalid room-message packet length');
    }
    final bodyEnd = _headerBytes + textLength;
    final expectedTag = _tag(
      siteId: siteId,
      roomId: roomId,
      eventId: eventId,
      packetWithoutTag: Uint8List.sublistView(packet, 0, bodyEnd),
    );
    final receivedTag = Uint8List.sublistView(packet, bodyEnd);
    if (!_constantTimeEquals(expectedTag, receivedTag)) {
      throw const FormatException('room-message HMAC mismatch');
    }
    return utf8.decode(
      Uint8List.sublistView(packet, _headerBytes, bodyEnd),
      allowMalformed: false,
    );
  }

  static Uint8List _tag({
    required String siteId,
    required String roomId,
    required String eventId,
    required Uint8List packetWithoutTag,
  }) {
    final context = utf8.encode('$siteId\u0000$roomId\u0000$eventId\u0000');
    final authenticated = Uint8List.fromList([...context, ...packetWithoutTag]);
    final digest = Hmac(
      sha256,
      SiteKeyProvisioning.demoKey(siteId),
    ).convert(authenticated);
    return Uint8List.fromList(digest.bytes.sublist(0, _tagBytes));
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
