import 'dart:typed_data';

import 'stt_engine.dart';

/// Small development stub so the app can exercise the STT integration path
/// before a real offline engine is wired in.
final class FakeOfflineSttEngine implements OfflineSttEngine {
  const FakeOfflineSttEngine({
    this.transcript = 'fake transcript: help needed near gate b',
    this.confidence = 0.42,
    this.modelId = 'fake-offline-stt',
  });

  final String transcript;
  final double confidence;
  final String modelId;

  @override
  Future<void> warmUp() async {}

  @override
  Future<SttResult> transcribe(Uint8List pcm16le, {int sampleRateHz = 16000}) async {
    if (pcm16le.isEmpty) {
      throw StateError('fake STT received empty PCM input');
    }
    final inferenceMs = (pcm16le.length / (sampleRateHz * 2)).ceil();
    return SttResult(
      text: transcript,
      confidence: confidence,
      inferenceMs: inferenceMs,
      modelId: modelId,
    );
  }

  @override
  Future<void> close() async {}
}
