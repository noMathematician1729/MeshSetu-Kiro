import 'dart:typed_data';

import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/core/protocol/envelope_codec.dart';
import 'package:test/test.dart';

void main() {
  test('protobuf round trip', () {
    final source = MeshEnvelope(
      objectId: 7,
      eventId: 'event',
      siteId: 'site',
      roomId: 'room',
      createdAtMs: 1,
      expiresAtMs: 2,
      hopCount: 0,
      hopLimit: 5,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: Uint8List.fromList([1, 2]),
      originEphemeralId: 9,
      traceId: Uint8List.fromList([3]),
    );
    final result = EnvelopeCodec.decode(EnvelopeCodec.encode(source));

    expect(result.objectId, source.objectId);
    expect(result.eventId, source.eventId);
    expect(result.siteId, source.siteId);
    expect(result.roomId, source.roomId);
    expect(result.createdAtMs, source.createdAtMs);
    expect(result.expiresAtMs, source.expiresAtMs);
    expect(result.hopCount, source.hopCount);
    expect(result.hopLimit, source.hopLimit);
    expect(result.priority, source.priority);
    expect(result.payloadType, source.payloadType);
    expect(result.originEphemeralId, source.originEphemeralId);
    expect(result.payload, orderedEquals(source.payload));
    expect(result.traceId, orderedEquals(source.traceId));
  });
}
