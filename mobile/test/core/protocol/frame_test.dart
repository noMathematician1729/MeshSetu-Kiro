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

  test('malformed frames fail before use', () {
    expect(() => FrameCodec.decode(Uint8List(15)), throwsArgumentError);
    expect(
      () => FrameCodec.decode(Uint8List(16)..[0] = 9),
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
}
