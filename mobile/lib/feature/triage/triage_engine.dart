import '../../core/model/model.dart';

/// Bible §13.2. `incidentType` stays a plain string on the wire
/// (`StructuredSos.incident_type`); this enum is the app-side vocabulary.
enum IncidentType {
  medical,
  fire,
  structuralOrCrush,
  crowdOrStampede,
  missingPerson,
  other,
}

final class TriageOutput {
  const TriageOutput({
    required this.priority,
    required this.incidentType,
    required this.confidence,
    required this.rationale,
    required this.modelId,
  });

  final PriorityBand priority;
  final IncidentType incidentType;
  final double confidence;
  final List<String> rationale;
  final String modelId;
}

/// Bible §13.3 — deterministic critical-phrase rules. These run before any
/// optional classifier and can only force escalation, never suppress a
/// manual SOS (§20.5 checklist).
final class SafetyRules {
  static final _breathing = RegExp(
    r"not breathing|unconscious|cannot breathe|can.t breathe",
    caseSensitive: false,
  );
  static final _hazard = RegExp(
    r'fire|smoke|crush|stampede|trapped',
    caseSensitive: false,
  );

  TriageOutput? evaluate(String text) {
    if (_breathing.hasMatch(text)) {
      return const TriageOutput(
        priority: PriorityBand.p0Critical,
        incidentType: IncidentType.medical,
        confidence: 1.0,
        rationale: ['critical safety rule matched: breathing/consciousness'],
        modelId: 'rules:v1',
      );
    }
    if (_hazard.hasMatch(text)) {
      return const TriageOutput(
        priority: PriorityBand.p0Critical,
        incidentType: IncidentType.structuralOrCrush,
        confidence: 1.0,
        rationale: ['critical safety rule matched: fire/crush/stampede'],
        modelId: 'rules:v1',
      );
    }
    return null;
  }
}

/// Bible §13.5. No `TriageClassifier` (optional local model) is built here
/// — that's Dev C's secondary-ownership territory (§20.1) — so this always
/// falls through to the documented conservative fallback rather than
/// fabricating a classifier result.
abstract interface class TriageClassifier {
  Future<TriageOutput> predict(String transcript);
}

final class TriageEngine {
  const TriageEngine(this.rules, [this.classifier]);

  final SafetyRules rules;
  final TriageClassifier? classifier;

  Future<TriageOutput> triage(String transcript) async {
    final forced = rules.evaluate(transcript);
    if (forced != null) return forced;
    final classifier = this.classifier;
    if (classifier == null) {
      return const TriageOutput(
        priority: PriorityBand.p1High,
        incidentType: IncidentType.other,
        confidence: 0.0,
        rationale: ['no classifier installed; conservative fallback'],
        modelId: 'fallback',
      );
    }
    try {
      return await classifier.predict(transcript);
    } catch (_) {
      return const TriageOutput(
        priority: PriorityBand.p1High,
        incidentType: IncidentType.other,
        confidence: 0.0,
        rationale: ['model unavailable; conservative fallback'],
        modelId: 'fallback',
      );
    }
  }
}
