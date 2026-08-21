import 'dart:typed_data';

import 'package:meshsetu_mobile/core/protocol/frame.dart';
import 'package:test/test.dart';

void main() {
  test('fragmentation round trips at all mtu sizes', () {
    final bytes = Uint8List.fromList(List.generate(10000, (i) => i % 251));
    for (final mtu in [23, 100, 185, 247, 517]) {
      final source = mtu == 23 ? Uint8List.sublistView(bytes, 0, 1500) : bytes;
      final frames = fragment(
        objectId: 42,
        priority: 1,
        encrypted: source,
        mtu: mtu,
      );
      final buffer = ReassemblyBuffer(frames.length);
      final shuffled = List.of(frames)..shuffle();
      for (final f in shuffled) {
        buffer.add(FrameCodec.decode(FrameCodec.encode(f)));
      }
      expect(buffer.complete(), isTrue);
      expect(buffer.join(), orderedEquals(source));
    }
  });

  test('max Android MTU never emits an oversized GATT attribute value', () {
    final frames = fragment(
      objectId: 42,
      priority: 1,
      encrypted: Uint8List(1000),
      mtu: 517,
    );

    expect(maxFragmentPayload(517), 496);
    expect(
      frames.every((frame) => FrameCodec.encode(frame).length <= 512),
      isTrue,
    );
  });

  test('malformed frames fail before use', () {
    expect(() => FrameCodec.decode(Uint8List(15)), throwsArgumentError);
    expect(
      () => FrameCodec.decode(Uint8List(16)..[0] = 9),
      throwsArgumentError,
    );
  });

  test('largest supported signed object ID round trips unchanged', () {
    const objectId = 0x7FFFFFFFFFFFFFFF;
    final encoded = FrameCodec.encode(
      MeshFrame(
        type: FrameType.data,
        priority: 1,
        flags: 0,
        objectId: objectId,
        sequence: 0,
        count: 1,
        payload: Uint8List.fromList([1]),
      ),
    );
    expect(FrameCodec.decode(encoded).objectId, objectId);
  });

  test('rejects noncanonical signed object IDs', () {
    expect(
      () => fragment(
        objectId: -1,
        priority: 1,
        encrypted: Uint8List.fromList([1]),
        mtu: 23,
      ),
      throwsArgumentError,
    );
  });

  test('duplicate chunks are ignored', () {
    final frame = fragment(
      objectId: 42,
      priority: 1,
      encrypted: Uint8List.fromList([1, 2, 3]),
      mtu: 23,
    ).single;
    final buffer = ReassemblyBuffer(1);
    expect(buffer.add(frame), isTrue);
    expect(buffer.add(frame), isFalse);
    expect(buffer.received, 1);
  });

  test('reassembly rejects object/count mismatches and byte overflow', () {
    MeshFrame frame({
      required int objectId,
      required int count,
      int bytes = 1,
    }) => MeshFrame(
      type: FrameType.data,
      priority: 1,
      flags: 0,
      objectId: objectId,
      sequence: 0,
      count: count,
      payload: Uint8List(bytes),
    );

    final buffer = ReassemblyBuffer(1, objectId: 42, maxBytes: 2);
    expect(buffer.add(frame(objectId: 43, count: 1)), isFalse);
    expect(buffer.add(frame(objectId: 42, count: 2)), isFalse);
    expect(
      () => buffer.add(frame(objectId: 42, count: 1, bytes: 3)),
      throwsStateError,
    );
    expect(buffer.received, 0);
  });

  test('low MTU rejects objects that exceed the voice chunk budget', () {
    expect(
      () => fragment(
        objectId: 42,
        priority: 3,
        encrypted: Uint8List(2049),
        mtu: 23,
      ),
      throwsArgumentError,
    );
  });

  test('hello round trips and rejects unknown version', () {
    const hello = Hello(
      siteFingerprint: 42,
      ephemeralNodeId: 7,
      capabilities: 9,
      maxObjectBytes: 1024,
      nowEpochSec: 10,
    );
    expect(HelloCodec.decode(HelloCodec.encode(hello)), hello);
    final corrupted = HelloCodec.encode(hello)..[0] = 2;
    expect(HelloCodec.decode(corrupted), isNull);
  });
}
