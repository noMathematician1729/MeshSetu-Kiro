import 'dart:convert';
import 'dart:typed_data';

import '../../core/model/model.dart';

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

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'incidentType': incidentType,
        'transcript': _truncateUtf8(transcript, maxTranscriptUtf8Bytes),
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
    );
  }

  static String _truncateUtf8(String value, int maxBytes) {
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
