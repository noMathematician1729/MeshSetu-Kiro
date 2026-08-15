import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/mesh_gatt.dart';

void main() {
  test('metadata round trips and rejects wrong length', () {
    const source = DiscoveryMetadata(
      fingerprint: 0x0102030405060708,
      connectionToken: 42,
      capabilities: 3,
    );
    expect(DiscoveryMetadata.decode(source.encode()), source);
    expect(DiscoveryMetadata.decode(Uint8List(12)), isNull);
  });

  test('connection owner is deterministic', () {
    expect(shouldInitiate(1, 2), isTrue);
    expect(shouldInitiate(2, 1), isFalse);
    expect(shouldInitiate(3, 3), isFalse);
  });
}
