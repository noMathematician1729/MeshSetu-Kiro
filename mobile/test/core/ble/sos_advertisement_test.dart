import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/sos_advertisement.dart';

void main() {
  test('compact SOS advertisement round trips and keeps its dedupe key', () {
    const alert = MeshSosAdvertisement(
      siteFingerprint: 0x12345678,
      originId: 0x87654321,
      sequence: 42,
      flags: MeshSosAdvertisement.alertFlag | MeshSosAdvertisement.testFlag,
      ttl: 4,
    );

    final decoded = MeshSosAdvertisement.decode(alert.encode());

    expect(decoded, isNotNull);
    expect(decoded!.isTest, isTrue);
    expect(decoded.dedupeKey, '305419896:2271560481:42');
  });

  test('compact SOS advertisement rejects a corrupt CRC and exhausted TTL', () {
    const alert = MeshSosAdvertisement(
      siteFingerprint: 1,
      originId: 2,
      sequence: 3,
      flags: MeshSosAdvertisement.alertFlag,
      ttl: 1,
    );
    final corrupt = Uint8List.fromList(alert.encode())..[13] ^= 1;
    final exhausted = Uint8List.fromList(alert.encode())..[12] = 0;

    expect(MeshSosAdvertisement.decode(corrupt), isNull);
    expect(MeshSosAdvertisement.decode(exhausted), isNull);
  });
}
