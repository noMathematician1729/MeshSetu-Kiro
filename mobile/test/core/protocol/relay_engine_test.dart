import 'dart:typed_data';

import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/core/protocol/frame.dart';
import 'package:meshsetu_mobile/core/protocol/relay_engine.dart';
import 'package:meshsetu_mobile/core/protocol/secure_envelope.dart';
import 'package:test/test.dart';

class _RecordingStore implements RelayStore {
  final List<MeshEnvelope> stored = [];

  @override
  void persist(MeshEnvelope envelope) => stored.add(envelope);
}

void main() {
  test('persists once and enqueues next hop', () async {
    final crypto = AeadEnvelope(List.filled(32, 7));
    final store = _RecordingStore();
    final engine = MeshRelayEngine(
      siteId: 'site',
      crypto: crypto,
      store: store,
      clockMs: () => 100,
    );
    final source = MeshEnvelope(
      objectId: 11,
      eventId: 'event',
      siteId: 'site',
      roomId: 'room',
      createdAtMs: 1,
      expiresAtMs: 1000,
      hopCount: 0,
      hopLimit: 2,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: Uint8List.fromList([9]),
      originEphemeralId: 1,
    );
    final encrypted = await crypto.encrypt(source);
    final frames = fragment(
      objectId: source.objectId,
      priority: 1,
      encrypted: encrypted.bytes,
      mtu: 185,
    ).toList()..shuffle();

    RelayResult result = const RelayResult([], []);
    for (final frame in frames) {
      result = await engine.receive('a', FrameCodec.encode(frame));
    }

    expect(store.stored.length, 1);
    expect(result.controlFrames, isNotEmpty);
    expect(result.metrics.where((m) => m.kind == 'object_complete').length, 1);
    expect(engine.nextOutbound(nowMs: 100)?.objectId, 11);
  });

  test('rejects wrong site and duplicates', () async {
    final crypto = AeadEnvelope(List.filled(32, 8));
    final store = _RecordingStore();
    final engine = MeshRelayEngine(
      siteId: 'site',
      crypto: crypto,
      store: store,
      clockMs: () => 100,
    );
    final source = MeshEnvelope(
      objectId: 12,
      eventId: 'event',
      siteId: 'other',
      roomId: 'room',
      createdAtMs: 1,
      expiresAtMs: 1000,
      hopCount: 0,
      hopLimit: 2,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: Uint8List.fromList([9]),
      originEphemeralId: 1,
    );
    final blob = await crypto.encrypt(source);
    final frame = FrameCodec.encode(
      fragment(
        objectId: source.objectId,
        priority: 1,
        encrypted: blob.bytes,
        mtu: 185,
      ).single,
    );
    final result = await engine.receive('a', frame);
    expect(result.metrics.any((m) => m.kind == 'wrong_site'), isTrue);
    expect(store.stored, isEmpty);
  });
}
