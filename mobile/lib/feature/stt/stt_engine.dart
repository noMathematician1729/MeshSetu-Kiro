import 'dart:typed_data';

/// Bible §12.1 — the frozen contract Dev C implements and Dev B/networking
/// code consumes. Networking and UI code must call only this interface so
/// the STT backend (whisper.cpp vs sherpa-onnx) can change without touching
/// product code.
final class SttResult {
  const SttResult({
    required this.text,
    required this.confidence,
    required this.inferenceMs,
    required this.modelId,
  });

  final String text, modelId;
  final double confidence;
  final int inferenceMs;
}

abstract interface class OfflineSttEngine {
  Future<void> warmUp();
  Future<SttResult> transcribe(Uint8List pcm16le, {int sampleRateHz = 16000});
  Future<void> close();
}

/// Stub used until Dev C wires a real engine in via native FFI. Bible
/// §20.6: "App can continue when `OfflineSttEngine` returns failure" and
/// §12.7: never fabricate a confidence number — this always fails cleanly
/// rather than returning fake text, so manual/voice SOS keeps working with
/// no transcript attached.
final class NullSttEngine implements OfflineSttEngine {
  const NullSttEngine();

  @override
  Future<void> warmUp() async {}

  @override
  Future<SttResult> transcribe(Uint8List pcm16le, {int sampleRateHz = 16000}) {
    throw StateError('no OfflineSttEngine installed');
  }

  @override
  Future<void> close() async {}
}
