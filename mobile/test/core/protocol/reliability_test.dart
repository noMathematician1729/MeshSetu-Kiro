import 'dart:typed_data';

import 'package:meshsetu_mobile/core/protocol/frame.dart';
import 'package:meshsetu_mobile/core/protocol/protocol_metrics.dart';
import 'package:test/test.dart';

void main() {
  test('missing bitmap and loss hook are deterministic', () {
    final frames = fragment(
      objectId: 1,
      priority: 1,
      encrypted: Uint8List.fromList(List.generate(8, (i) => i)),
      mtu: 23,
    );
    final buffer = ReassemblyBuffer(frames.length);
    buffer.add(frames[0]);
    expect(buffer.missingBitmap(), orderedEquals([0x02]));

    final lossy = LossyFrameInterceptor(dropEvery: 2);
    expect(lossy.apply(Uint8List.fromList([1])), isNotNull);
    expect(lossy.apply(Uint8List.fromList([1])), isNull);
  });

  test('metrics are single line and escaped', () {
    final output = StringBuffer();
    JsonLineMetricSink(output).write(
      const ProtocolMetric(
        timeMs: 1,
        peer: 'abcdefghijklmnop',
        kind: 'x"y',
        detail: 'line\nvalue',
      ),
    );
    expect(
      output.toString(),
      '{"time_ms":1,"kind":"x\\"y","peer":"abcdefghijkl","detail":"line\\nvalue"}\n',
    );
  });
}
