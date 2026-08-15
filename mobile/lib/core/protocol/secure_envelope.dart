import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../model/model.dart';
import 'envelope_codec.dart';

const int _formatVersion = 1;
const int _ivBytes = 12;

/// Port of `in.meshsetu.protocol.CryptoEnvelope` / `AeadEnvelope`
/// (Kotlin `SecureEnvelope.kt`).
///
/// Wire format: `[version:1][siteIdLen:2][siteId bytes][iv:12][ciphertext+tag]`.
/// The site ID rides in the blob and is folded into the AEAD's additional
/// authenticated data (`[version:1][objectId:8][siteIdLen:2][siteId bytes]`),
/// so a tampered/foreign site ID fails authentication even though it's not
/// itself encrypted — matches the upstream Kotlin format exactly (this was
/// a breaking wire-format change from the previous port).
///
/// Deliberate deviation from the Kotlin source: `package:cryptography`'s AES-GCM
/// API is `Future`-based (there is no synchronous AES-GCM in the Dart
/// ecosystem), so this interface — and [MeshRelayEngine]'s methods that call
/// it — are `async` here even though the Kotlin originals are synchronous.
/// This matches the Bible's own reference code (§8.6 `onCompleteObject` is
/// already `Future<void>`), so the wider app was always going to be async at
/// this boundary.
///
/// `decrypt` returns `null` on any failure (bad format, tampered tag, wrong
/// object id, wrong site id) rather than a typed error, mirroring how the
/// only caller (`MeshRelayEngine.receive`) treats a Kotlin `Result` failure:
/// it discards the exception and just records a metric.
abstract interface class CryptoEnvelope {
  Future<EncryptedObject> encrypt(MeshEnvelope value);
  Future<MeshEnvelope?> decrypt(EncryptedObject value);
}

class AeadEnvelope implements CryptoEnvelope {
  AeadEnvelope(List<int> keyBytes, {Random? random})
    : _secretKey = SecretKeyData(keyBytes),
      _random = random ?? Random.secure();

  static final AesGcm _algorithm = AesGcm.with256bits();
  final SecretKeyData _secretKey;
  final Random _random;

  @override
  Future<EncryptedObject> encrypt(MeshEnvelope value) async {
    final site = utf8.encode(value.siteId);
    if (site.length > 0x7FFF) {
      throw ArgumentError('site id is too long');
    }
    final iv = Uint8List.fromList(
      List<int>.generate(_ivBytes, (_) => _random.nextInt(256)),
    );
    final plaintext = EnvelopeCodec.encode(value);
    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: _secretKey,
      nonce: iv,
      aad: _aad(value.objectId, site),
    );
    final blob = BytesBuilder()
      ..addByte(_formatVersion)
      ..add(_uint16(site.length))
      ..add(site)
      ..add(secretBox.nonce)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);
    return EncryptedObject(
      objectId: value.objectId,
      trafficClass: _trafficClassFor(value.payloadType),
      bytes: blob.toBytes(),
      expiresAtMs: value.expiresAtMs,
      createdAtMs: value.createdAtMs,
    );
  }

  @override
  Future<MeshEnvelope?> decrypt(EncryptedObject value) async {
    try {
      if (value.bytes.length <= 1 + 2 + _ivBytes + 16) return null;
      final input = ByteData.sublistView(value.bytes);
      if (input.getUint8(0) != _formatVersion) return null;
      final siteLength = input.getUint16(1, Endian.big);
      final siteStart = 3;
      if (siteLength < 0 || siteStart + siteLength > value.bytes.length) {
        return null;
      }
      final site = value.bytes.sublist(siteStart, siteStart + siteLength);
      final ivStart = siteStart + siteLength;
      if (ivStart + _ivBytes > value.bytes.length) return null;
      final iv = value.bytes.sublist(ivStart, ivStart + _ivBytes);
      final rest = value.bytes.sublist(ivStart + _ivBytes);
      if (rest.length <= 16) return null;
      final cipherText = rest.sublist(0, rest.length - 16);
      final mac = Mac(rest.sublist(rest.length - 16));
      final plaintext = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: iv, mac: mac),
        secretKey: _secretKey,
        aad: _aad(value.objectId, site),
      );
      final envelope = EnvelopeCodec.decode(Uint8List.fromList(plaintext));
      if (envelope.objectId != value.objectId) return null;
      if (envelope.siteId != utf8.decode(site)) return null;
      return envelope;
    } catch (_) {
      return null;
    }
  }

  Uint8List _aad(int objectId, List<int> site) {
    final out = BytesBuilder()
      ..addByte(_formatVersion)
      ..add(_int64(objectId))
      ..add(_uint16(site.length))
      ..add(site);
    return out.toBytes();
  }

  Uint8List _int64(int value) =>
      (ByteData(8)..setInt64(0, value, Endian.big)).buffer.asUint8List();

  Uint8List _uint16(int value) =>
      (ByteData(2)..setUint16(0, value, Endian.big)).buffer.asUint8List();
}

TrafficClass _trafficClassFor(PayloadType type) => switch (type) {
  PayloadType.voiceObject ||
  PayloadType.voiceManifest => TrafficClass.voiceEvidence,
  PayloadType.roomMessage => TrafficClass.roomMessage,
  PayloadType.ack => TrafficClass.controlAck,
  PayloadType.responderUpdate => TrafficClass.authorityControl,
  PayloadType.beaconObservation => TrafficClass.telemetry,
  PayloadType.structuredSos => TrafficClass.sosStructured,
};
