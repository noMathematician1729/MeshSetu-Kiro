import 'dart:typed_data';

import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:test/test.dart';

void main() {
  test('rejects expired envelope', () {
    expect(
      () => MeshEnvelope(
        objectId: 1,
        eventId: 'e',
        siteId: 's',
        roomId: 'r',
        createdAtMs: 10,
        expiresAtMs: 10,
        hopCount: 0,
        hopLimit: 1,
        priority: PriorityBand.p0Critical,
        payloadType: PayloadType.ack,
        payload: Uint8List.fromList([1]),
        originEphemeralId: 2,
      ),
      throwsArgumentError,
    );
  });
}
