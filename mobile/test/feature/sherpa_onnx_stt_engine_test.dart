import 'dart:typed_data';

import 'package:meshsetu_mobile/feature/stt/sherpa_onnx_stt_engine.dart';
import 'package:test/test.dart';

void main() {
  test('pcm16leToFloat32Samples converts signed little-endian PCM', () {
    final pcm = Uint8List.fromList([
      0x00, 0x00, // 0
      0x00, 0x80, // -32768
      0xff, 0x7f, // 32767
    ]);
    final samples = pcm16leToFloat32Samples(pcm);
    expect(samples.length, 3);
    expect(samples[0], 0.0);
    expect(samples[1], -1.0);
    expect(samples[2], closeTo(32767 / 32768.0, 1e-6));
  });

  test('pcm16leToFloat32Samples rejects odd byte lengths', () {
    expect(
      () => pcm16leToFloat32Samples(Uint8List.fromList([1])),
      throwsArgumentError,
    );
  });
}
