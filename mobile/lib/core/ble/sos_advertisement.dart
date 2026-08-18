import 'dart:typed_data';

/// Compact, unauthenticated emergency alert carried in BLE manufacturer data.
/// It is deliberately limited to routing/alert information; the encrypted
/// MeshEnvelope remains the source of rich SOS details.
class MeshSosAdvertisement {
  const MeshSosAdvertisement({
    required this.siteFingerprint,
    required this.originId,
    required this.sequence,
    required this.flags,
    required this.ttl,
  });

  static const int version = 1;
  static const int byteLength = 14;
  static const int alertFlag = 1;
  static const int testFlag = 1 << 7;

  final int siteFingerprint;
  final int originId;
  final int sequence;
  final int flags;
  final int ttl;

  bool get isTest => flags & testFlag != 0;
  String get dedupeKey => '$siteFingerprint:$originId:$sequence';

  Uint8List encode() {
    final bytes = ByteData(byteLength);
    bytes.setUint8(0, version);
    bytes.setUint32(1, siteFingerprint & 0xffffffff, Endian.big);
    bytes.setUint32(5, originId & 0xffffffff, Endian.big);
    bytes.setUint16(9, sequence & 0xffff, Endian.big);
    bytes.setUint8(11, flags & 0xff);
    bytes.setUint8(12, ttl.clamp(0, 255));
    bytes.setUint8(13, _crc8(bytes.buffer.asUint8List(0, 13)));
    return bytes.buffer.asUint8List();
  }

  static MeshSosAdvertisement? decode(Uint8List bytes) {
    if (bytes.length != byteLength || bytes[0] != version) return null;
    if (_crc8(bytes.sublist(0, 13)) != bytes[13] || bytes[12] == 0) {
      return null;
    }
    final input = ByteData.sublistView(bytes);
    return MeshSosAdvertisement(
      siteFingerprint: input.getUint32(1, Endian.big),
      originId: input.getUint32(5, Endian.big),
      sequence: input.getUint16(9, Endian.big),
      flags: input.getUint8(11),
      ttl: input.getUint8(12),
    );
  }

  static int _crc8(List<int> bytes) {
    var crc = 0;
    for (final value in bytes) {
      crc ^= value;
      for (var bit = 0; bit < 8; bit++) {
        crc = crc & 0x80 == 0 ? crc << 1 : (crc << 1) ^ 0x07;
        crc &= 0xff;
      }
    }
    return crc;
  }
}
