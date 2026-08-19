import 'dart:convert';
import 'dart:typed_data';

import '../../core/model/model.dart';

/// The privacy-bounded reporter snapshot placed only in a rich, encrypted SOS
/// envelope. It deliberately excludes free-form medical notes; those remain in
/// encrypted local onboarding storage. [reporterUid] is stable and
/// pseudonymous, allowing a control room to correlate packets without relying
/// on a transient mesh origin ID.
final class SosReporter {
  const SosReporter({
    required this.reporterUid,
    required this.name,
    required this.phone,
    required this.language,
    required this.bloodGroup,
    required this.primaryContactName,
    required this.primaryContactPhone,
  });

  static const maxReporterUidUtf8Bytes = 12;
  static const maxNameUtf8Bytes = 64;
  static const maxPhoneUtf8Bytes = 24;
  static const maxLanguageUtf8Bytes = 12;
  static const maxBloodGroupUtf8Bytes = 8;
  static const maxContactNameUtf8Bytes = 48;

  final String reporterUid;
  final String name;
  final String phone;
  final String language;
  final String bloodGroup;
  final String primaryContactName;
  final String primaryContactPhone;

  Map<String, String> toJson() => {
    'uid': StructuredSosPayload.truncateUtf8(
      reporterUid,
      maxReporterUidUtf8Bytes,
    ),
    'name': StructuredSosPayload.truncateUtf8(name, maxNameUtf8Bytes),
    'phone': StructuredSosPayload.truncateUtf8(phone, maxPhoneUtf8Bytes),
    'language': StructuredSosPayload.truncateUtf8(
      language,
      maxLanguageUtf8Bytes,
    ),
    'bloodGroup': StructuredSosPayload.truncateUtf8(
      bloodGroup,
      maxBloodGroupUtf8Bytes,
    ),
    'primaryContactName': StructuredSosPayload.truncateUtf8(
      primaryContactName,
      maxContactNameUtf8Bytes,
    ),
    'primaryContactPhone': StructuredSosPayload.truncateUtf8(
      primaryContactPhone,
      maxPhoneUtf8Bytes,
    ),
  };

  static SosReporter? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = value.cast<Object?, Object?>();
    final uid = map['uid'];
    final name = map['name'];
    final phone = map['phone'];
    final language = map['language'];
    final bloodGroup = map['bloodGroup'];
    final contactName = map['primaryContactName'];
    final contactPhone = map['primaryContactPhone'];
    if (uid is! String ||
        name is! String ||
        phone is! String ||
        language is! String ||
        bloodGroup is! String ||
        contactName is! String ||
        contactPhone is! String) {
      return null;
    }
    return SosReporter(
      reporterUid: uid,
      name: name,
      phone: phone,
      language: language,
      bloodGroup: bloodGroup,
      primaryContactName: contactName,
      primaryContactPhone: contactPhone,
    );
  }
}

/// App-level content of a `STRUCTURED_SOS` [MeshEnvelope] payload (Bible
/// §3.3 `StructuredSos` proto message). The envelope/frame/fragmentation
/// wire format stays protobuf (byte-identical with the Kotlin port); this
/// inner payload is JSON rather than a second generated proto message —
/// it's opaque `bytes` to the transport either way, and adding a protoc
/// toolchain step for one message isn't worth it for a hackathon build.
final class StructuredSosPayload {
  static const maxTranscriptUtf8Bytes = 160;

  const StructuredSosPayload({
    required this.incidentType,
    required this.transcript,
    required this.sttConfidence,
    required this.triagePriority,
    required this.triageConfidence,
    required this.hazards,
    required this.rationale,
    required this.inputMode,
    this.locationHint = '',
    this.logicalZone = '',
    this.voiceClipId = '',
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.locationCapturedAtMs,
    this.reporter,
  });

  final String incidentType;
  final String transcript;
  final double sttConfidence;
  final PriorityBand triagePriority;
  final double triageConfidence;
  final List<String> hazards;
  final List<String> rationale;
  final InputMode inputMode;
  final String locationHint, logicalZone, voiceClipId;
  final double? latitude, longitude, accuracyM;
  final int? locationCapturedAtMs;
  final SosReporter? reporter;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'incidentType': incidentType,
        'transcript': truncateUtf8(transcript, maxTranscriptUtf8Bytes),
        'sttConfidence': sttConfidence,
        'triagePriority': triagePriority.name,
        'triageConfidence': triageConfidence,
        'hazards': hazards,
        'rationale': rationale,
        'inputMode': inputMode.name,
        'locationHint': locationHint,
        'logicalZone': logicalZone,
        'voiceClipId': voiceClipId,
        'lat': latitude,
        'lon': longitude,
        'accuracyM': accuracyM,
        'locationCapturedAtMs': locationCapturedAtMs,
        if (reporter != null) 'reporter': reporter!.toJson(),
      }),
    ),
  );

  static StructuredSosPayload decode(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    return StructuredSosPayload(
      incidentType: map['incidentType'] as String,
      transcript: map['transcript'] as String,
      sttConfidence: (map['sttConfidence'] as num).toDouble(),
      triagePriority: PriorityBand.values.byName(
        map['triagePriority'] as String,
      ),
      triageConfidence: (map['triageConfidence'] as num).toDouble(),
      hazards: (map['hazards'] as List<Object?>).cast<String>(),
      rationale: (map['rationale'] as List<Object?>).cast<String>(),
      inputMode: InputMode.values.byName(map['inputMode'] as String),
      locationHint: map['locationHint'] as String? ?? '',
      logicalZone: map['logicalZone'] as String? ?? '',
      voiceClipId: map['voiceClipId'] as String? ?? '',
      latitude: (map['lat'] as num?)?.toDouble(),
      longitude: (map['lon'] as num?)?.toDouble(),
      accuracyM: (map['accuracyM'] as num?)?.toDouble(),
      locationCapturedAtMs: (map['locationCapturedAtMs'] as num?)?.toInt(),
      reporter: SosReporter.fromJson(map['reporter']),
    );
  }

  static String truncateUtf8(String value, int maxBytes) {
    final output = StringBuffer();
    var bytes = 0;
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      final characterBytes = utf8.encode(character).length;
      if (bytes + characterBytes > maxBytes) break;
      output.write(character);
      bytes += characterBytes;
    }
    return output.toString();
  }
}
