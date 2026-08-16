import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/model/model.dart';
import '../triage/triage_engine.dart';
import '../voice/voice_recorder.dart';
import 'sos_repository.dart';

/// SOS composition (Bible §3.2, `feature/sos`). Deliberately the shortest
/// possible path from "user is in danger" to "persisted + relaying":
/// deterministic triage runs inline (no async model to wait on), STT/voice
/// attach later without blocking this screen — a manual SOS is never
/// blocked (§20.5 checklist).
class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key, required this.siteId, required this.roomId});

  final String siteId, roomId;

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  final _textController = TextEditingController();
  final _voiceRecorder = VoiceRecorder();
  bool _sending = false;
  bool _recording = false;
  String? _status;
  String? _lastEventId;

  @override
  void dispose() {
    _textController.dispose();
    unawaited(_voiceRecorder.dispose());
    super.dispose();
  }

  Future<void> _sendSos() async {
    setState(() {
      _sending = true;
      _status = null;
    });
    try {
      final result = await _createAndFinalize(InputMode.text);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _lastEventId = result.eventId;
        _status =
            'SOS sent — priority ${result.triage.priority.name}, '
            '${result.triage.incidentType.name}';
      });
      _textController.clear();
    } catch (error) {
      if (mounted) setState(() => _status = 'SOS failed: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<({String eventId, TriageOutput triage})> _createAndFinalize(
    InputMode inputMode,
  ) async {
    final text = _textController.text.trim();
    final repo = ref.read(sosRepositoryProvider);
    final eventId = await repo.createDraft(
      SosInput(
        siteId: widget.siteId,
        roomId: widget.roomId,
        inputMode: inputMode,
        rawText: text,
      ),
    );
    final triage = await TriageEngine(SafetyRules()).triage(text);
    await repo.attachTriage(eventId, triage);
    await repo.finalizeAndEnqueue(eventId);
    return (eventId: eventId, triage: triage);
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      try {
        await _voiceRecorder.stop();
      } catch (error) {
        if (mounted) {
          setState(() {
            _recording = false;
            _status = 'Voice capture failed: $error';
          });
        }
      }
      return;
    }
    try {
      var eventId = _lastEventId;
      if (eventId == null) {
        setState(() => _sending = true);
        final result = await _createAndFinalize(InputMode.voice);
        eventId = result.eventId;
        if (mounted) {
          setState(() {
            _sending = false;
            _lastEventId = eventId;
            _status = 'SOS queued — recording voice evidence';
          });
        }
      }
      setState(() => _recording = true);
      final bytes = await _voiceRecorder.start();
      if (!mounted) return;
      setState(() => _recording = false);
      await ref
          .read(voiceRepositoryProvider)
          .attachToSos(
            sosEventId: eventId,
            siteId: widget.siteId,
            roomId: widget.roomId,
            encoded: bytes,
          );
      if (!mounted) return;
      setState(() => _status = '$_status · voice evidence queued');
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _recording = false;
          _status = 'Voice SOS failed: $error';
        });
      }
    }
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
              'Describe what is happening. This is sent at the highest '
              'transport priority the mesh supports.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What is happening?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.sos),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _sending ? null : _sendSos,
              label: Text(_sending ? 'Sending…' : 'Send SOS'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!, style: const TextStyle(color: Colors.green)),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(
                _recording
                    ? 'Stop (auto-stops at 10s)'
                    : _lastEventId == null
                    ? 'Record voice SOS'
                    : 'Attach voice evidence',
              ),
              onPressed: _sending ? null : _toggleVoice,
            ),
          ],
        ),
      ),
    );
  }
}
