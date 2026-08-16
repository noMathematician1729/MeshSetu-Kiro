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
  // ignore: prefer_initializing_formals
  VoiceRecorder({Duration cap = const Duration(seconds: 10)}) : _cap = cap;

  final Duration _cap;
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _capTimer;
  Completer<Uint8List>? _finished;

  /// Raw mono PCM stream for STT. This is intentionally a separate path from
  /// the current Opus file recording: STT needs `pcm16le`, while the mesh clip
  /// path wants a compressed file payload.
  Future<Stream<Uint8List>> startPcmStream() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('microphone permission denied');
    }
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
  }

  static VoiceRecorder withCap(Duration cap) => VoiceRecorder(cap: cap);

  /// Captures a short raw PCM clip for STT experimentation.
  ///
  /// This path is intentionally separate from the existing Opus file
  /// recording used for mesh transport. STT needs raw `pcm16le` samples.
  Future<Uint8List> recordPcmClip({Duration? duration}) async {
    final stream = await startPcmStream();
    final bytes = BytesBuilder(copy: false);
    final subscription = stream.listen(bytes.add);
    try {
      await Future<void>.delayed(duration ?? _cap);
      await _recorder.stop();
      await subscription.cancel();
      final pcm = bytes.takeBytes();
      if (pcm.isEmpty) {
        throw StateError('recording produced no PCM audio');
      }
      return pcm;
    } catch (_) {
      await _recorder.stop();
      await subscription.cancel();
      rethrow;
    }
  }

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
