import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/model/model.dart';
import '../sos/sos_payload.dart';
import '../voice/voice_repository.dart';

/// Bible §15.1/§3.4: the gateway phone receives mesh objects exactly like
/// any other peer (Dev A's `MeshTransportCoordinator`); this bridge only
/// pushes already-verified/reassembled `StructuredSos` events on to the
/// configured dashboard URL over local Wi-Fi or an HTTPS tunnel.
class GatewayBridge {
  GatewayBridge({required this.baseUrl, required this.demoKey});

  final Uri baseUrl;
  final String demoKey;

  Future<void> postToDashboard(Map<String, Object?> event) async {
    final uri = baseUrl.resolve('/api/events');
    final response = await http
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            'x-meshsetu-demo-key': demoKey,
          },
          body: jsonEncode(event),
        )
        .timeout(const Duration(seconds: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('dashboard HTTP ${response.statusCode}');
    }
  }

  /// Bible §15.4 dashboard fields, built from a reassembled envelope +
  /// its decoded [StructuredSosPayload].
  Map<String, Object?> eventJson({
    required MeshEnvelope envelope,
    required StructuredSosPayload sos,
    int? relayLatencyMs,
  }) => {
    'event_id': envelope.eventId,
    'priority': sos.triagePriority.name,
    'incident_type': sos.incidentType,
    'transcript': sos.transcript.isEmpty ? null : sos.transcript,
    'zone': sos.logicalZone.isEmpty ? null : sos.logicalZone,
    'latitude': sos.latitude,
    'longitude': sos.longitude,
    'accuracy_m': sos.accuracyM,
    'location_captured_at_ms': sos.locationCapturedAtMs,
    'room': envelope.roomId,
    'hops': envelope.hopCount,
    'relay_latency_ms': relayLatencyMs,
    'voice_clip_id': sos.voiceClipId.isEmpty ? null : sos.voiceClipId,
    'audio_state': sos.voiceClipId.isEmpty ? null : 'queued',
  };

  Map<String, Object?> voiceCompleteJson(VoiceObjectPayload voice) => {
    'event_id': voice.sosEventId,
    'priority': 'unknown',
    'incident_type': 'unknown',
    'voice_clip_id': voice.clipId,
    'audio_state': 'complete',
  };
}

// The actual forwarding trigger lives in `app/mesh_bridge_client.dart`:
// `MeshTransportCoordinator.incoming` only exists in the background
// isolate, so the UI-isolate bridge client forwards `structuredSos`
// objects using this class's `postToDashboard`/`eventJson` as they arrive
// over the cross-isolate `mesh_received` channel.
