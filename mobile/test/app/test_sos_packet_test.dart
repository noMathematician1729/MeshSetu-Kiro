import 'package:meshsetu_mobile/app/test_sos_packet.dart';
import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:test/test.dart';

void main() {
  test('one-packet SOS smoke payload is 100 bytes and readable', () {
    final envelope = MeshEnvelope(
      objectId: 1,
      eventId: 'test-event',
      siteId: 'demo-site',
      roomId: 'public',
      createdAtMs: 1,
      expiresAtMs: 2,
      hopCount: 0,
      hopLimit: 4,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: TestSosPacket.payload,
      originEphemeralId: 1,
    );

    expect(envelope.payload, hasLength(TestSosPacket.payloadLength));
    expect(TestSosPacket.matches(envelope), isTrue);
  });
}
