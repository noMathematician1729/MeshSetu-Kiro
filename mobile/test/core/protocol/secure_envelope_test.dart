import 'dart:typed_data';

import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/core/protocol/secure_envelope.dart';
import 'package:test/test.dart';

void main() {
  test('authenticated round trip and tamper rejection', () async {
    final crypto = AeadEnvelope(List.generate(32, (i) => i));
    final source = MeshEnvelope(
      objectId: 8,
      eventId: 'event',
      siteId: 'site',
      roomId: 'room',
      createdAtMs: 1,
      expiresAtMs: 2,
      hopCount: 0,
      hopLimit: 5,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: Uint8List.fromList([1]),
      originEphemeralId: 9,
    );
    final encrypted = await crypto.encrypt(source);
    final decoded = await crypto.decrypt(encrypted);
    expect(decoded, isNotNull);
    expect(decoded!.objectId, source.objectId);
    expect(decoded.eventId, source.eventId);
    expect(decoded.payload, orderedEquals(source.payload));

    final tamperedBytes = Uint8List.fromList(encrypted.bytes);
    tamperedBytes[tamperedBytes.length - 1] ^= 1;
    final tampered = EncryptedObject(
      objectId: encrypted.objectId,
      trafficClass: encrypted.trafficClass,
      bytes: tamperedBytes,
      expiresAtMs: encrypted.expiresAtMs,
    );
    expect(await crypto.decrypt(tampered), isNull);
  });

  test('site metadata is authenticated', () async {
    final crypto = AeadEnvelope(List.generate(32, (i) => i));
    final source = MeshEnvelope(
      objectId: 9,
      eventId: 'event',
      siteId: 'site',
      roomId: 'room',
      createdAtMs: 1,
      expiresAtMs: 2,
      hopCount: 0,
      hopLimit: 5,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: Uint8List.fromList([1]),
      originEphemeralId: 9,
    );
    final encrypted = await crypto.encrypt(source);
    final tamperedBytes = Uint8List.fromList(encrypted.bytes);
    // Byte 3 is the first byte of the site-id region (after 1-byte version +
    // 2-byte length prefix); it's authenticated via AAD but not itself
    // encrypted, so tampering it must still fail decryption.
    tamperedBytes[3] ^= 0xFF;
    final tampered = EncryptedObject(
      objectId: encrypted.objectId,
      trafficClass: encrypted.trafficClass,
      bytes: tamperedBytes,
      expiresAtMs: encrypted.expiresAtMs,
    );
    expect(await crypto.decrypt(tampered), isNull);
  });
}
