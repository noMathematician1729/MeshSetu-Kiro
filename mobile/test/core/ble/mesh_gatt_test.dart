import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/mesh_gatt.dart';

void main() {
  test('beacon metadata round trips bounded UTF-8 anchor IDs', () {
    final encoded = const BeaconMetadata('gate-east').encode();
    expect(BeaconMetadata.decode(encoded)?.anchorId, 'gate-east');
  });

  test('beacon metadata rejects malformed and oversized payloads', () {
    expect(BeaconMetadata.decode(Uint8List.fromList([1, 0xFF])), isNull);
    expect(() => BeaconMetadata('x' * 25).encode(), throwsArgumentError);
  });
}
