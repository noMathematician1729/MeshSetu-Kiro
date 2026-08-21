import 'dart:typed_data';

/// Compact, unauthenticated emergency alert carried in BLE manufacturer data.
/// It is deliberately limited to routing/alert information; the encrypted
/// MeshEnvelope remains the source of rich SOS details.
///
/// Two wire versions exist and both are accepted on receive:
///
/// * v1 (14 bytes) — routing only. Kept so already-deployed phones stay
///   interoperable.
/// * v2 (20 bytes) — appends the sender's 6-byte pseudonymous reporter UID.
///   A receiver with internet resolves that UID against the control-room
///   backend to obtain the same incident detail the admin dashboard shows.
///
/// The UID is pseudonymous: it carries no name, phone number or GPS fix. The
/// mapping from UID to identity only exists in the backend profile table.
class MeshSosAdvertisement {
  const MeshSosAdvertisement({
    required this.siteFingerprint,
    required this.originId,
    required this.sequence,
    required this.flags,
    required this.ttl,
    this.reporterUidHex = '',
  });

  static const int version = 1;
  static const int versionWithReporter = 2;
  static const int byteLength = 14;
  static const int byteLengthWithReporter = 20;
  static const int reporterUidBytes = 6;
  static const int alertFlag = 1;
  static const int testFlag = 1 << 7;

  final int siteFingerprint;
  final int originId;
  final int sequence;
  final int flags;
  final int ttl;

  /// Lowercase 12-character hex UID, or empty when the sender did not
  /// advertise one (v1 packet, or a device without a saved profile).
  final String reporterUidHex;

  bool get isTest => flags & testFlag != 0;
  bool get hasReporterUid => reporterUidHex.length == reporterUidBytes * 2;
  String get dedupeKey => '$siteFingerprint:$originId:$sequence';

  MeshSosAdvertisement withTtl(int value) => MeshSosAdvertisement(
    siteFingerprint: siteFingerprint,
    originId: originId,
    sequence: sequence,
    flags: flags,
    ttl: value,
    reporterUidHex: reporterUidHex,
  );

  Uint8List encode() {
    final uid = hasReporterUid ? _decodeHex(reporterUidHex) : null;
    final length = uid == null ? byteLength : byteLengthWithReporter;
    final bytes = ByteData(length);
    bytes.setUint8(0, uid == null ? version : versionWithReporter);
    bytes.setUint32(1, siteFingerprint & 0xffffffff, Endian.big);
    bytes.setUint32(5, originId & 0xffffffff, Endian.big);
    bytes.setUint16(9, sequence & 0xffff, Endian.big);
    bytes.setUint8(11, flags & 0xff);
    bytes.setUint8(12, ttl.clamp(0, 255));
    if (uid != null) {
      for (var index = 0; index < reporterUidBytes; index++) {
        bytes.setUint8(13 + index, uid[index]);
      }
    }
    final crcOffset = length - 1;
    bytes.setUint8(
      crcOffset,
      _crc8(bytes.buffer.asUint8List(0, crcOffset)),
    );
    return bytes.buffer.asUint8List();
  }

  static MeshSosAdvertisement? decode(Uint8List bytes) {
    final carriesReporter = bytes.length == byteLengthWithReporter &&
        bytes.isNotEmpty &&
        bytes[0] == versionWithReporter;
    final legacy =
        bytes.length == byteLength && bytes.isNotEmpty && bytes[0] == version;
    if (!carriesReporter && !legacy) return null;
    final crcOffset = bytes.length - 1;
    if (_crc8(bytes.sublist(0, crcOffset)) != bytes[crcOffset] ||
        bytes[12] == 0) {
      return null;
    }
    final input = ByteData.sublistView(bytes);
    return MeshSosAdvertisement(
      siteFingerprint: input.getUint32(1, Endian.big),
      originId: input.getUint32(5, Endian.big),
      sequence: input.getUint16(9, Endian.big),
      flags: input.getUint8(11),
      ttl: input.getUint8(12),
      reporterUidHex: carriesReporter
          ? _encodeHex(bytes.sublist(13, 13 + reporterUidBytes))
          : '',
    );
  }

  /// Normalizes an onboarding reporter UID for advertising. Returns an empty
  /// string when the value is not a usable 6-byte hex UID.
  static String normalizeReporterUid(String? value) {
    final candidate = (value ?? '').trim().toLowerCase();
    if (candidate.length != reporterUidBytes * 2) return '';
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(candidate)) return '';
    if (int.tryParse(candidate.substring(0, 8), radix: 16) == 0 &&
        int.tryParse(candidate.substring(8), radix: 16) == 0) {
      return '';
    }
    return candidate;
  }

  static Uint8List _decodeHex(String value) => Uint8List.fromList([
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ]);

  static String _encodeHex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

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
