import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'stt_engine.dart';

const _modelDirName = 'sherpa-onnx-zipformer-small-en-2023-06-26';

final class SherpaOnnxEnglishSttEngine implements OfflineSttEngine {
  SherpaOnnxEnglishSttEngine({
    this.assetRoot = 'assets/models/$_modelDirName',
    this.modelId = _modelDirName,
  });

  final String assetRoot;
  final String modelId;

  sherpa_onnx.OfflineRecognizer? _recognizer;
  String? _resolvedModelDir;

  @override
  Future<void> warmUp() async {
    if (_recognizer != null) return;

    sherpa_onnx.initBindings();
    final modelDir = await _ensureModelFiles();

    final model = sherpa_onnx.OfflineModelConfig(
      transducer: sherpa_onnx.OfflineTransducerModelConfig(
        encoder: '$modelDir/encoder-epoch-99-avg-1.int8.onnx',
        decoder: '$modelDir/decoder-epoch-99-avg-1.onnx',
        joiner: '$modelDir/joiner-epoch-99-avg-1.int8.onnx',
      ),
      tokens: '$modelDir/tokens.txt',
      numThreads: 2,
      debug: false,
      provider: 'cpu',
      modelType: 'transducer',
    );

    _recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(model: model),
    );
    _resolvedModelDir = modelDir;
  }

  @override
  Future<SttResult> transcribe(
    Uint8List pcm16le, {
    int sampleRateHz = 16000,
  }) async {
    await warmUp();
    if (pcm16le.isEmpty) {
      throw StateError('sherpa-onnx received empty PCM input');
    }

    final recognizer = _recognizer;
    if (recognizer == null) {
      throw StateError('sherpa-onnx recognizer was not initialized');
    }

    final samples = pcm16leToFloat32Samples(pcm16le);
    final stream = recognizer.createStream();
    final stopwatch = Stopwatch()..start();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRateHz);
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      stopwatch.stop();
      return SttResult(
        text: result.text.trim(),
        confidence: 0.0,
        inferenceMs: stopwatch.elapsedMilliseconds,
        modelId: modelId,
      );
    } finally {
      stream.free();
    }
  }

  @override
  Future<void> close() async {
    _recognizer?.free();
    _recognizer = null;
    _resolvedModelDir = null;
  }

  Future<String> _ensureModelFiles() async {
    if (_resolvedModelDir != null) return _resolvedModelDir!;

    final supportDir = await getApplicationSupportDirectory();
    final targetDir = Directory('${supportDir.path}/models/$_modelDirName');
    await targetDir.create(recursive: true);

    for (final relativePath in _requiredFiles) {
      final assetPath = '$assetRoot/$relativePath';
      final output = File('${targetDir.path}/$relativePath');
      if (await output.exists()) continue;

      final data = await _loadRequiredAsset(assetPath);
      await output.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    _resolvedModelDir = targetDir.path;
    return targetDir.path;
  }
}

Future<ByteData> _loadRequiredAsset(String assetPath) async {
  try {
    return await rootBundle.load(assetPath);
  } catch (_) {
    throw StateError(
      'Missing model asset $assetPath. '
      'Follow mobile/assets/models/README.md to download the sherpa-onnx '
      'English model bundle into the repo, then rebuild the app with '
      '`flutter clean && flutter run`.',
    );
  }
}

Float32List pcm16leToFloat32Samples(Uint8List pcm16le) {
  if (pcm16le.length.isOdd) {
    throw ArgumentError('pcm16le byte length must be even');
  }
  final input = ByteData.sublistView(pcm16le);
  final out = Float32List(pcm16le.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final sample = input.getInt16(i * 2, Endian.little);
    out[i] = sample / 32768.0;
  }
  return out;
}

const List<String> _requiredFiles = <String>[
  'encoder-epoch-99-avg-1.int8.onnx',
  'decoder-epoch-99-avg-1.onnx',
  'joiner-epoch-99-avg-1.int8.onnx',
  'tokens.txt',
];
