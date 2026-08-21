import 'dart:io';
import 'dart:typed_data';

import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/core/protocol/frame.dart';
import 'package:meshsetu_mobile/core/protocol/relay_engine.dart';
import 'package:meshsetu_mobile/core/protocol/secure_envelope.dart';
import 'package:test/test.dart';

class _RecordingStore extends RelayStore {
  final List<MeshEnvelope> stored = [];

  @override
  void persist(MeshEnvelope envelope, {Uint8List? encryptedBytes}) =>
      stored.add(envelope);
}

class _AckTrackingStore extends RelayStore {
  _AckTrackingStore(this.acked);
  final List<int> acked;

  @override
  void persist(MeshEnvelope envelope, {Uint8List? encryptedBytes}) {}

  @override
  void markAck(int objectId, String peerId) => acked.add(objectId);
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

  test('retains outbox until custody ack and retries on nack', () async {
    final crypto = AeadEnvelope(List.filled(32, 3));
    final acked = <int>[];
    final store = _AckTrackingStore(acked);
    final engine = MeshRelayEngine(
      siteId: 'site',
      crypto: crypto,
      store: store,
      clockMs: () => 100,
    );
    final source = MeshEnvelope(
      objectId: 13,
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
    await engine.submit(source);
    final outbound = engine.nextOutbound(nowMs: 100)!;
    engine.markSent(outbound, 'peer');

    final nack = FrameCodec.encode(
      MeshFrame(
        type: FrameType.nack,
        priority: 1,
        flags: 0,
        objectId: source.objectId,
        sequence: 0,
        count: 1,
        payload: Uint8List.fromList([1]),
      ),
    );
    await engine.receive('peer', nack);
    expect(engine.nextOutbound(nowMs: 100)?.objectId, source.objectId);

    engine.markSent(outbound, 'peer');
    final ackPayload = (ByteData(
      8,
    )..setInt64(0, source.objectId, Endian.big)).buffer.asUint8List();
    final ack = FrameCodec.encode(
      MeshFrame(
        type: FrameType.custodyAck,
        priority: 1,
        flags: 0,
        objectId: source.objectId,
        sequence: 0,
        count: 1,
        payload: ackPayload,
      ),
    );
    await engine.receive('peer', ack);
    expect(acked, [source.objectId]);
    expect(engine.nextOutbound(nowMs: 100), isNull);
  });

  test('ack timeout retains the object for a later custody retry', () async {
    final crypto = AeadEnvelope(List.filled(32, 4));
    final engine = MeshRelayEngine(
      siteId: 'site',
      crypto: crypto,
      store: _RecordingStore(),
      clockMs: () => 100,
    );
    final source = MeshEnvelope(
      objectId: 131,
      eventId: 'event',
      siteId: 'site',
      roomId: 'room',
      createdAtMs: 1,
      expiresAtMs: 100000,
      hopCount: 0,
      hopLimit: 2,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: Uint8List.fromList([9]),
      originEphemeralId: 1,
    );
    await engine.submit(source);
    final outbound = engine.nextOutbound(nowMs: 100)!;
    engine.markSent(outbound, 'peer', nowMs: 100);

    engine.retryExpired(nowMs: 8100);

    expect(
      engine.drainMetrics().any(
        (metric) =>
            metric.kind == 'ack_timeout' && metric.objectId == source.objectId,
      ),
      isTrue,
    );
    expect(engine.nextOutbound(nowMs: 8100)?.objectId, source.objectId);
  });

  test('only the peer holding custody can acknowledge a sent object', () async {
    final crypto = AeadEnvelope(List.filled(32, 6));
    final acked = <int>[];
    final engine = MeshRelayEngine(
      siteId: 'site',
      crypto: crypto,
      store: _AckTrackingStore(acked),
      clockMs: () => 100,
    );
    final source = MeshEnvelope(
      objectId: 133,
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
    await engine.submit(source);
    engine.markSent(engine.nextOutbound(nowMs: 100)!, 'peer-a');
    final payload = (ByteData(
      8,
    )..setInt64(0, source.objectId, Endian.big)).buffer.asUint8List();
    final result = await engine.receive(
      'peer-b',
      FrameCodec.encode(
        MeshFrame(
          type: FrameType.custodyAck,
          priority: 1,
          flags: 0,
          objectId: source.objectId,
          sequence: 0,
          count: 1,
          payload: payload,
        ),
      ),
    );

    expect(acked, isEmpty);
    expect(
      result.metrics.any(
        (metric) =>
            metric.kind == 'unexpected_ack' &&
            metric.objectId == source.objectId,
      ),
      isTrue,
    );
  });

  test(
    'duplicate delivery is acknowledged without duplicate persistence',
    () async {
      final crypto = AeadEnvelope(List.filled(32, 5));
      final store = _RecordingStore();
      final engine = MeshRelayEngine(
        siteId: 'site',
        crypto: crypto,
        store: store,
        clockMs: () => 100,
      );
      final source = MeshEnvelope(
        objectId: 132,
        eventId: 'event',
        siteId: 'site',
        roomId: 'room',
        createdAtMs: 1,
        expiresAtMs: 1000,
        hopCount: 0,
        hopLimit: 0,
        priority: PriorityBand.p0Critical,
        payloadType: PayloadType.structuredSos,
        payload: Uint8List.fromList([9]),
        originEphemeralId: 1,
      );
      final encrypted = await crypto.encrypt(source);
      final frame = FrameCodec.encode(
        fragment(
          objectId: source.objectId,
          priority: 1,
          encrypted: encrypted.bytes,
          mtu: 185,
        ).single,
      );

      final first = await engine.receive('peer', frame);
      final duplicate = await engine.receive('peer', frame);

      expect(store.stored, hasLength(1));
      expect(
        FrameCodec.decode(first.controlFrames.single).type,
        FrameType.custodyAck,
      );
      expect(
        FrameCodec.decode(duplicate.controlFrames.single).type,
        FrameType.custodyAck,
      );
    },
  );

  test('file store restores pending outbox', () {
    final directory = Directory.systemTemp.createTempSync('meshsetu-relay');
    addTearDown(() => directory.deleteSync(recursive: true));

    final first = FileRelayStore(directory);
    final value = EncryptedObject(
      objectId: 14,
      trafficClass: TrafficClass.sosStructured,
      bytes: Uint8List.fromList([1, 2]),
      expiresAtMs: 1000,
      createdAtMs: 10,
    );
    first.enqueue(value);

    final restored = FileRelayStore(directory).pending(100).single;
    expect(restored.objectId, value.objectId);
    expect(restored.trafficClass, value.trafficClass);
    expect(restored.bytes, orderedEquals(value.bytes));
    expect(restored.expiresAtMs, value.expiresAtMs);
    expect(restored.createdAtMs, value.createdAtMs);

    first.markAck(value.objectId, 'peer');
    expect(FileRelayStore(directory).pending(100), isEmpty);
    expect(
      File('${directory.path}/acks/${value.objectId}.ack').existsSync(),
      isTrue,
    );
  });

  test('file store removes expired pending entries', () {
    final directory = Directory.systemTemp.createTempSync('meshsetu-expired');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = FileRelayStore(directory);
    store.enqueue(
      EncryptedObject(
        objectId: 15,
        trafficClass: TrafficClass.roomMessage,
        bytes: Uint8List.fromList([1]),
        expiresAtMs: 10,
      ),
    );

    expect(store.pending(10), isEmpty);
    expect(File('${directory.path}/outbox/15.bin').existsSync(), isFalse);
  });
}
