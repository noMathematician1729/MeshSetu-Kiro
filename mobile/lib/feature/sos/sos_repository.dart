import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../core/data/database.dart';
import '../../core/model/model.dart';
import '../stt/stt_engine.dart';
import '../triage/triage_engine.dart';
import '../location/location_capture.dart';
import '../onboarding/onboarding_repository.dart';
import 'sos_payload.dart';

const _uuid = Uuid();

/// Bible §3.2 step 1-2 input: what the composer screen collects before any
/// STT/triage runs. A manual SOS with just [rawText]/tap must be usable on
/// its own — STT and triage are attached later and are both optional.
final class SosInput {
  const SosInput({
    required this.siteId,
    required this.roomId,
    required this.inputMode,
    this.rawText = '',
    this.priority = PriorityBand.p1High,
    this.ttlMs = 15 * 60 * 1000,
  });

  final String siteId, roomId;
  final InputMode inputMode;
  final String rawText;
  final PriorityBand priority;
  final int ttlMs;
}

/// Bible §20.2 frozen interface — the contract Dev B provides to the rest
/// of the Flutter app. `feature/voice` and `feature/stt`/`feature/triage`
/// call into this without needing to know it's backed by Drift + the mesh
/// transport outbox.
abstract interface class SosRepository {
  Future<String> createDraft(SosInput input);
  Future<void> attachTranscript(String eventId, SttResult stt);
  Future<void> attachLocation(String eventId, SosLocation location);
  Future<void> attachVoice(String eventId, Uint8List encoded);
  Future<void> attachTriage(String eventId, TriageOutput output);
  Future<void> finalizeAndEnqueue(String eventId);
}

class DriftSosRepository implements SosRepository {
  DriftSosRepository(this._db, this._onboarding);

  final MeshDatabase _db;
  final OnboardingRepository _onboarding;

  @override
  Future<String> createDraft(SosInput input) async {
    if (input.siteId.trim().isEmpty || input.roomId.trim().isEmpty) {
      throw ArgumentError('siteId and roomId must not be blank');
    }
    if (input.ttlMs <= 0) throw ArgumentError('ttlMs must be positive');
    final eventId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    // Bible §20.5: "SOS is persisted before model work begins" — this row
    // exists (state=created) the instant the draft is made, independent of
    // whether STT/triage ever attach anything to it.
    await _db
        .into(_db.outboxEvents)
        .insert(
          OutboxEventsCompanion.insert(
            eventId: eventId,
            siteId: input.siteId,
            roomId: input.roomId,
            payloadType: PayloadType.structuredSos.name,
            inputMode: Value(input.inputMode.name),
            rawText: Value(input.rawText),
            priority: input.priority.name,
            state: const Value('created'),
            createdAtMs: now,
            updatedAtMs: now,
            expiresAtMs: now + input.ttlMs,
          ),
        );
    return eventId;
  }

  @override
  Future<void> attachTranscript(String eventId, SttResult stt) =>
      (_db.update(
        _db.outboxEvents,
      )..where((t) => t.eventId.equals(eventId))).write(
        OutboxEventsCompanion(
          transcript: Value(stt.text),
          updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  @override
  Future<void> attachLocation(String eventId, SosLocation location) async {
    if (!location.isValid) throw ArgumentError('location is invalid');
    final row = await (_db.select(
      _db.outboxEvents,
    )..where((t) => t.eventId.equals(eventId))).getSingle();
    final triage = _triageRecord(row.triageJson) ?? <String, Object?>{};
    triage['location'] = {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'accuracyM': location.accuracyM,
      'capturedAtMs': location.capturedAtMs,
    };
    await (_db.update(
      _db.outboxEvents,
    )..where((t) => t.eventId.equals(eventId))).write(
      OutboxEventsCompanion(
        triageJson: Value(jsonEncode(triage)),
        updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> attachVoice(String eventId, Uint8List encoded) async {
    if (encoded.isEmpty) throw ArgumentError('voice payload must not be empty');
    await (_db.update(
      _db.outboxEvents,
    )..where((t) => t.eventId.equals(eventId))).write(
      OutboxEventsCompanion(
        voicePath: Value('inline:${encoded.length}b'),
        updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> attachTriage(String eventId, TriageOutput output) async {
    final row = await (_db.select(
      _db.outboxEvents,
    )..where((t) => t.eventId.equals(eventId))).getSingle();
    final encoded = <String, Object?>{
      ...?_triageRecord(_encodeTriage(output)),
      if (_locationFrom(row.triageJson) case final location?)
        'location': location,
    };
    await (_db.update(
      _db.outboxEvents,
    )..where((t) => t.eventId.equals(eventId))).write(
      OutboxEventsCompanion(
        triageJson: Value(jsonEncode(encoded)),
        priority: Value(output.priority.name),
        updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> finalizeAndEnqueue(String eventId) async {
    final row = await (_db.select(
      _db.outboxEvents,
    )..where((t) => t.eventId.equals(eventId))).getSingle();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (row.expiresAtMs <= now) {
      await _db.markState(eventId, 'expired', now);
      throw StateError('SOS draft expired');
    }
    final profile = await _onboarding.load();
    if (profile == null) {
      throw StateError('Complete emergency profile setup before sending SOS');
    }
    final priority = PriorityBand.values.byName(row.priority);
    final location = _locationFrom(row.triageJson);
    final payload = StructuredSosPayload(
      incidentType: _incidentTypeFrom(row.triageJson),
      transcript: row.transcript ?? row.rawText ?? '',
      sttConfidence: 0,
      triagePriority: row.inputMode == InputMode.voice.name
          ? PriorityBand.p0Critical
          : priority,
      triageConfidence: _confidenceFrom(row.triageJson),
      hazards: const [],
      rationale: _rationaleFrom(row.triageJson),
      inputMode: InputMode.values.byName(row.inputMode ?? InputMode.tap.name),
      voiceClipId: _voiceClipIdFrom(row.voicePath),
      latitude: (location?['latitude'] as num?)?.toDouble(),
      longitude: (location?['longitude'] as num?)?.toDouble(),
      accuracyM: (location?['accuracyM'] as num?)?.toDouble(),
      locationCapturedAtMs: (location?['capturedAtMs'] as num?)?.toInt(),
      reporter: SosReporter(
        reporterUid: profile.reporterUid,
        name: profile.name,
        phone: profile.phone,
        language: profile.language,
        bloodGroup: profile.medicalProfile.bloodGroup,
        primaryContactName: profile.primaryContact.name,
        primaryContactPhone: profile.primaryContact.phone,
      ),
    );
    await (_db.update(
      _db.outboxEvents,
    )..where((t) => t.eventId.equals(eventId))).write(
      OutboxEventsCompanion(
        objectId: Value(_randomObjectId()),
        payload: Value(payload.encode()),
        state: const Value('ready'),
        updatedAtMs: Value(now),
      ),
    );
  }

  String _encodeTriage(TriageOutput o) => jsonEncode({
    'incidentType': o.incidentType.name,
    'confidence': o.confidence,
    'rationale': o.rationale,
    'modelId': o.modelId,
  });

  Map<String, Object?>? _triageRecord(String? encoded) {
    if (encoded == null) return null;
    try {
      return (jsonDecode(encoded) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  String _incidentTypeFrom(String? triageJson) =>
      (_triageRecord(triageJson)?['incidentType'] as String?) ?? 'other';

  double _confidenceFrom(String? triageJson) =>
      ((_triageRecord(triageJson)?['confidence'] as num?)?.toDouble()) ?? 0;

  List<String> _rationaleFrom(String? triageJson) =>
      ((_triageRecord(triageJson)?['rationale'] as List?)?.cast<String>()) ??
      const [];

  Map<String, Object?>? _locationFrom(String? triageJson) {
    final location = _triageRecord(triageJson)?['location'];
    return location is Map ? location.cast<String, Object?>() : null;
  }

  String _voiceClipIdFrom(String? voicePath) =>
      voicePath?.startsWith('clip:') == true
      ? voicePath!.substring('clip:'.length)
      : '';

  int _randomObjectId() {
    final random = Random.secure();
    final high = random.nextInt(1 << 31);
    final low = random.nextInt(1 << 32);
    final value = (high << 32) | low;
    return value == 0 ? 1 : value;
  }
}
