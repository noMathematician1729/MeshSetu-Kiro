import 'dart:typed_data';

import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/core/protocol/outbound_scheduler.dart';
import 'package:test/test.dart';

void main() {
  test('emergency preempts bulk and expiry is dropped', () {
    final q = OutboundScheduler();
    q.enqueue(
      EncryptedObject(
        objectId: 1,
        trafficClass: TrafficClass.voiceEvidence,
        bytes: Uint8List.fromList([1]),
        expiresAtMs: 100,
      ),
      0,
    );
    q.enqueue(
      EncryptedObject(
        objectId: 2,
        trafficClass: TrafficClass.sosStructured,
        bytes: Uint8List.fromList([1]),
        expiresAtMs: 100,
      ),
      0,
    );
    q.enqueue(
      EncryptedObject(
        objectId: 3,
        trafficClass: TrafficClass.roomMessage,
        bytes: Uint8List.fromList([1]),
        expiresAtMs: 1,
      ),
      0,
    );
    expect(q.next(0)?.objectId, 2);
    expect(q.next(2)?.objectId, 1);
  });
}
