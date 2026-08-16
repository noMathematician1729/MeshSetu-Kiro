import 'dart:typed_data';

import 'package:meshsetu_mobile/feature/stt/fake_stt_engine.dart';
import 'package:test/test.dart';

void main() {
  test('FakeOfflineSttEngine returns deterministic development output', () async {
    const engine = FakeOfflineSttEngine(
      transcript: 'help needed',
      confidence: 0.75,
      modelId: 'fake-test',
    );
    final result = await engine.transcribe(
      Uint8List.fromList(List<int>.filled(32000, 0)),
    );
    expect(result.text, 'help needed');
    expect(result.confidence, 0.75);
    expect(result.modelId, 'fake-test');
    expect(result.inferenceMs, greaterThan(0));
  });
}
