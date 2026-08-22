import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/ble/device_key_store.dart';

/// Decoded content from a room-message packet. [senderName] is null when the
/// packet was encoded with the v1 format (no sender field).
class RoomMessageContent {
  const RoomMessageContent({required this.text, this.senderName});

  final String text;

  /// Display name of the sender as stored in their onboarding profile. Null
  /// for packets encoded by older builds that used the v1 format.
  final String? senderName;
}

/// Authenticated application payload carried inside a mesh envelope.
///
/// CEAL validates its active compact SOS advertisement with CRC8 and includes
/// an HMAC helper for authenticated fragments. Room messages need stronger
/// integrity than CRC, so this format uses a 128-bit truncated HMAC-SHA256 in
/// addition to the transport's AES-GCM authentication.
///
/// ## Wire layouts
///
/// **v1 (legacy, read-only):**
/// `[magic:4][version=1:1][textLength:2][utf8Text][hmac:16]`
/// — header 7 bytes, no sender field.
///
/// **v2 (current):**
/// `[magic:4][version=2:1][senderNameLength:1][textLength:2]
///  [utf8SenderName][utf8Text][hmac:16]`
/// — header 8 bytes, sender name up to [maxSenderNameBytes] UTF-8 bytes.
///
/// The HMAC context is identical for both versions: the NUL-delimited
/// `siteId\0roomId\0eventId\0` is prepended to every byte of the header +
/// body region before computing the tag, so the version byte, lengths, name,
/// and text are all authenticated.
abstract final class RoomMessagePacketCodec {
  static const List<int> _magic = [0x4D, 0x53, 0x52, 0x4D]; // "MSRM"
  static const int _versionLegacy = 1;
  static const int _version = 2;

  // v1 header: magic(4) + version(1) + textLength(2) = 7
  static const int _v1HeaderBytes = 7;

  // v2 header: magic(4) + version(1) + senderNameLength(1) + textLength(2) = 8
  static const int _v2HeaderBytes = 8;

  static const int _tagBytes = 16;
  static const int maxTextBytes = 4096;

  /// Maximum UTF-8 byte length of the sender name carried in a v2 packet.
  /// 64 bytes accommodates even long unicode display names while staying well
  /// inside the worst-case fragmentation budget.
  static const int maxSenderNameBytes = 64;

  /// Encodes a v2 packet. [senderName] is truncated to [maxSenderNameBytes]
  /// without splitting a multi-byte rune. An empty or null name is stored as
  /// a zero-length field (valid v2, decoded as an empty string).
  static Uint8List encode({
    required String siteId,
    required String roomId,
    required String eventId,
    required String text,
    String? senderName,
  }) {
    if (siteId.trim().isEmpty ||
        roomId.trim().isEmpty ||
        eventId.trim().isEmpty) {
      throw ArgumentError('site, room, and event ids must not be blank');
    }
    final message = text.trim();
    final textBytes = Uint8List.fromList(utf8.encode(message));
    if (textBytes.isEmpty || textBytes.length > maxTextBytes) {
      throw ArgumentError('message must be 1..$maxTextBytes UTF-8 bytes');
    }
    final nameBytes = _truncateUtf8(senderName ?? '', maxSenderNameBytes);
    if (nameBytes.length > maxSenderNameBytes) {
      // Defensive: _truncateUtf8 must never exceed the limit.
      throw ArgumentError(
        'sender name exceeds $maxSenderNameBytes UTF-8 bytes after truncation',
      );
    }

    final headerAndBody = Uint8List(
      _v2HeaderBytes + nameBytes.length + textBytes.length,
    );
    headerAndBody.setRange(0, _magic.length, _magic);
    headerAndBody[4] = _version;
    headerAndBody[5] = nameBytes.length;
    ByteData.sublistView(headerAndBody).setUint16(6, textBytes.length, Endian.big);
    headerAndBody.setRange(_v2HeaderBytes, _v2HeaderBytes + nameBytes.length, nameBytes);
    headerAndBody.setRange(
      _v2HeaderBytes + nameBytes.length,
      headerAndBody.length,
      textBytes,
    );

    final tag = _tag(
      siteId: siteId,
      roomId: roomId,
      eventId: eventId,
      packetWithoutTag: headerAndBody,
    );
    return Uint8List.fromList([...headerAndBody, ...tag]);
  }

  /// Returns true when [packet] begins with the MSRM magic bytes and is long
  /// enough to plausibly be a v1 or v2 room-message packet.
  static bool isEncoded(Uint8List packet) =>
      packet.length >= _v1HeaderBytes + _tagBytes &&
      _constantTimeEquals(
        Uint8List.sublistView(packet, 0, _magic.length),
        Uint8List.fromList(_magic),
      );

  /// Decodes a v1 or v2 packet. Returns a [RoomMessageContent] with [senderName]
  /// null for legacy v1 packets and non-null (possibly empty) for v2.
  ///
  /// Throws [FormatException] when the packet is not a valid room-message
  /// packet, carries an unknown version, has a bad length, or the HMAC
  /// does not match.
  static RoomMessageContent decode({
    required String siteId,
    required String roomId,
    required String eventId,
    required Uint8List packet,
  }) {
    if (!isEncoded(packet)) {
      throw const FormatException('not a MeshSetu room-message packet');
    }
    final version = packet[4];
    if (version == _versionLegacy) {
      return _decodeV1(
        siteId: siteId,
        roomId: roomId,
        eventId: eventId,
        packet: packet,
      );
    }
    if (version == _version) {
      return _decodeV2(
        siteId: siteId,
        roomId: roomId,
        eventId: eventId,
        packet: packet,
      );
    }
    throw const FormatException('unsupported room-message packet version');
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static RoomMessageContent _decodeV1({
    required String siteId,
    required String roomId,
    required String eventId,
    required Uint8List packet,
  }) {
    final textLength = ByteData.sublistView(packet).getUint16(5, Endian.big);
    final expectedLength = _v1HeaderBytes + textLength + _tagBytes;
    if (textLength < 1 ||
        textLength > maxTextBytes ||
        packet.length != expectedLength) {
      throw const FormatException('invalid v1 room-message packet length');
    }
    final bodyEnd = _v1HeaderBytes + textLength;
    _verifyTag(
      siteId: siteId,
      roomId: roomId,
      eventId: eventId,
      packet: packet,
      bodyEnd: bodyEnd,
    );
    final text = utf8.decode(
      Uint8List.sublistView(packet, _v1HeaderBytes, bodyEnd),
      allowMalformed: false,
    );
    return RoomMessageContent(text: text);
  }

  static RoomMessageContent _decodeV2({
    required String siteId,
    required String roomId,
    required String eventId,
    required Uint8List packet,
  }) {
    if (packet.length < _v2HeaderBytes + _tagBytes) {
      throw const FormatException('v2 room-message packet too short');
    }
    final data = ByteData.sublistView(packet);
    final nameLength = packet[5];
    final textLength = data.getUint16(6, Endian.big);
    final expectedLength = _v2HeaderBytes + nameLength + textLength + _tagBytes;
    if (textLength < 1 ||
        textLength > maxTextBytes ||
        nameLength > maxSenderNameBytes ||
        packet.length != expectedLength) {
      throw const FormatException('invalid v2 room-message packet length');
    }
    final bodyEnd = _v2HeaderBytes + nameLength + textLength;
    _verifyTag(
      siteId: siteId,
      roomId: roomId,
      eventId: eventId,
      packet: packet,
      bodyEnd: bodyEnd,
    );
    final nameStart = _v2HeaderBytes;
    final textStart = nameStart + nameLength;
    final senderName = nameLength == 0
        ? ''
        : utf8.decode(
            Uint8List.sublistView(packet, nameStart, textStart),
            allowMalformed: false,
          );
    final text = utf8.decode(
      Uint8List.sublistView(packet, textStart, bodyEnd),
      allowMalformed: false,
    );
    return RoomMessageContent(text: text, senderName: senderName);
  }

  static void _verifyTag({
    required String siteId,
    required String roomId,
    required String eventId,
    required Uint8List packet,
    required int bodyEnd,
  }) {
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

  /// Returns the UTF-8 encoding of [value] truncated so it is at most
  /// [maxBytes] bytes long without splitting a multi-byte character.
  static Uint8List _truncateUtf8(String value, int maxBytes) {
    final encoded = utf8.encode(value);
    if (encoded.length <= maxBytes) return Uint8List.fromList(encoded);
    // Walk backwards from the limit to find the last valid UTF-8 boundary.
    var end = maxBytes;
    // UTF-8 continuation bytes are 0x80–0xBF. Step back until we land on
    // a leading byte (0x00–0x7F, 0xC0–0xFF).
    while (end > 0 && (encoded[end] & 0xC0) == 0x80) {
      end--;
    }
    return Uint8List.fromList(encoded.sublist(0, end));
  }
}
