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
/// Deliberate deviation from the Kotlin source: `package:cryptography`'s AES-GCM
/// API is `Future`-based (there is no synchronous AES-GCM in the Dart
/// ecosystem), so this interface — and [MeshRelayEngine]'s methods that call
/// it — are `async` here even though the Kotlin originals are synchronous.
/// This matches the Bible's own reference code (§8.6 `onCompleteObject` is
/// already `Future<void>`), so the wider app was always going to be async at
/// this boundary. The wire format and validation logic are unchanged.
///
/// `decrypt` returns `null` on any failure (bad format, tampered tag, wrong
/// object id) rather than a typed error, mirroring how the only caller
/// (`MeshRelayEngine.receive`) treats a Kotlin `Result` failure: it discards
/// the exception and just records a metric.
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
    final iv = Uint8List.fromList(
      List<int>.generate(_ivBytes, (_) => _random.nextInt(256)),
    );
    final plaintext = EnvelopeCodec.encode(value);
    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: _secretKey,
      nonce: iv,
      aad: _aad(value.objectId),
    );
    final blob = BytesBuilder()
      ..addByte(_formatVersion)
      ..add(secretBox.nonce)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);
    return EncryptedObject(
      objectId: value.objectId,
      trafficClass: _trafficClassFor(value.payloadType),
      bytes: blob.toBytes(),
      expiresAtMs: value.expiresAtMs,
    );
  }

  @override
  Future<MeshEnvelope?> decrypt(EncryptedObject value) async {
    try {
      if (value.bytes.length <= 1 + _ivBytes + 16) return null;
      if (value.bytes[0] != _formatVersion) return null;
      final iv = value.bytes.sublist(1, 1 + _ivBytes);
      final rest = value.bytes.sublist(1 + _ivBytes);
      final cipherText = rest.sublist(0, rest.length - 16);
      final mac = Mac(rest.sublist(rest.length - 16));
      final plaintext = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: iv, mac: mac),
        secretKey: _secretKey,
        aad: _aad(value.objectId),
      );
      final envelope = EnvelopeCodec.decode(Uint8List.fromList(plaintext));
      if (envelope.objectId != value.objectId) return null;
      return envelope;
    } catch (_) {
      return null;
    }
  }

  Uint8List _aad(int objectId) {
    final data = ByteData(8);
    data.setInt64(0, objectId, Endian.big);
    return data.buffer.asUint8List();
  }
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
