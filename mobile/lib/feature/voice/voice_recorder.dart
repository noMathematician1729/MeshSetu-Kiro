import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Bible §11/§20.5: 16 kHz mono capture, duration-capped (demo default 10s),
/// encoded locally before BLE fragmentation. Uses `record`'s built-in Opus
/// file encoder — no native FFI wrapper needed (`native/opus` in the Bible's
/// module layout was written assuming a hand-rolled libopus binding; the
/// `record` package already ships a platform Opus encoder, so that native
/// module is unnecessary here).
class VoiceRecorder {
  VoiceRecorder({this._cap = const Duration(seconds: 10)});

  final Duration _cap;
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _capTimer;
  Completer<Uint8List>? _finished;

  /// Starts recording; the returned future completes with the encoded
  /// bytes once [stop] is called or the duration cap is hit, whichever
  /// comes first.
  Future<Uint8List> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('microphone permission denied');
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.opus';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.opus,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    final finished = Completer<Uint8List>();
    _finished = finished;
    _capTimer = Timer(_cap, () => unawaited(stop()));
    return finished.future;
  }

  Future<void> stop() async {
    final finished = _finished;
    if (finished == null || finished.isCompleted) return;
    _capTimer?.cancel();
    try {
      final path = await _recorder.stop();
      final bytes = path == null
          ? Uint8List(0)
          : await File(path).readAsBytes();
      if (bytes.isEmpty) {
        finished.completeError(StateError('recording produced no audio'));
      } else {
        finished.complete(bytes);
      }
    } catch (error, stackTrace) {
      if (!finished.isCompleted) finished.completeError(error, stackTrace);
    } finally {
      _finished = null;
      _capTimer = null;
    }
  }

  Future<void> dispose() async {
    _capTimer?.cancel();
    await stop();
    await _recorder.dispose();
  }
}
