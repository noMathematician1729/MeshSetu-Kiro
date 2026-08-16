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

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'incidentType': incidentType,
        'transcript': transcript,
        'sttConfidence': sttConfidence,
        'triagePriority': triagePriority.name,
        'triageConfidence': triageConfidence,
        'hazards': hazards,
        'rationale': rationale,
        'inputMode': inputMode.name,
        'locationHint': locationHint,
        'logicalZone': logicalZone,
        'voiceClipId': voiceClipId,
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
    );
  }
}
