import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/providers.dart';
import '../../core/model/model.dart';
import '../location/location_capture.dart';
import '../triage/triage_engine.dart';
import '../voice/voice_recorder.dart';
import 'sos_repository.dart';

/// The real emergency action: persist first, record voice, capture location,
/// transcribe offline, then finalize one P0 structured SOS into the outbox.
class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key, required this.siteId, required this.roomId});

  final String siteId, roomId;

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  final _textController = TextEditingController();
  final _voiceRecorder = VoiceRecorder.withCap(const Duration(seconds: 10));
  bool _sending = false;
  String? _status;

  @override
  void dispose() {
    _textController.dispose();
    unawaited(_voiceRecorder.dispose());
    super.dispose();
  }

  Future<void> _sendSos() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _status = 'Persisting SOS draft…';
    });

    try {
      final repo = ref.read(sosRepositoryProvider);
      final rawText = _textController.text.trim();
      final eventId = await repo.createDraft(
        SosInput(
          siteId: widget.siteId,
          roomId: widget.roomId,
          inputMode: InputMode.voice,
          rawText: rawText,
        ),
      );

      // Request this before record's microphone permission request. Android
      // can drop one of two simultaneous runtime permission dialogs.
      _setStatus('SOS draft saved · checking location permission…');
      final locationPermission = await Permission.locationWhenInUse.request();
      final locationFuture = locationPermission.isGranted
          ? const LocationCapture().capture()
          : Future.value(
              const LocationCaptureResult.failure(
                LocationFailureReason.permissionDenied,
              ),
            );
      _setStatus('SOS draft saved · recording voice for up to 10 seconds…');
      String transcript = rawText;
      var sttStatus = 'voice unavailable';
      try {
        final pcm = await _voiceRecorder.recordPcmClip();
        _setStatus('Voice captured · transcribing offline…');
        final engine = ref.read(offlineSttEngineProvider);
        await engine.warmUp();
        final stt = await engine.transcribe(pcm);
        transcript = stt.text.trim().isEmpty ? rawText : stt.text.trim();
        if (stt.text.trim().isNotEmpty) {
          await repo.attachTranscript(eventId, stt);
        }
        sttStatus = stt.text.trim().isEmpty
            ? 'no words detected'
            : 'voice transcribed';
      } catch (_) {
        sttStatus = 'voice unavailable';
        _setStatus('Voice/STT unavailable · sending available SOS data…');
      }

      final locationResult = await locationFuture;
      final location = locationResult.location;
      final triage = await TriageEngine(SafetyRules()).triage(transcript);
      await repo.attachTriage(eventId, triage);
      if (location != null) await repo.attachLocation(eventId, location);
      await repo.finalizeAndEnqueue(eventId);

      if (!mounted) return;
      setState(() {
        _sending = false;
        _status = 'SOS queued for BLE · ${locationResult.status} · $sttStatus';
        _textController.clear();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _status = 'SOS failed after draft persistence: $error';
        });
      }
    }
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send SOS')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tap once, speak naturally, and the app will attach offline '
              'transcription and best-effort GPS before relaying the SOS.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Optional text fallback',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.sos),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _sending ? null : _sendSos,
                label: Text(_sending ? 'Recording / sending…' : 'SEND SOS'),
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(_status!),
            ],
          ],
        ),
      ),
    );
  }
}
