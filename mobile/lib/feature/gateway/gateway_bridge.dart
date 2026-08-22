import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/model/model.dart';
import '../sos/sos_payload.dart';
import '../voice/voice_repository.dart';

/// Bible §15.1/§3.4: the gateway phone receives mesh objects exactly like
/// any other peer (Dev A's `MeshTransportCoordinator`); this bridge only
/// pushes the original encrypted/reassembled mesh object to the configured
/// dashboard URL over local Wi-Fi. The Node backend independently verifies
/// and decrypts the packet; the gateway never supplies trusted SOS fields.
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
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('dashboard HTTP ${response.statusCode}');
    }
  }

  Future<void> postEncryptedObject({
    required String siteId,
    required int objectId,
    required List<int> packet,
    required int receivedAtMs,
    String? peerId,
  }) async {
    final response = await http
        .post(
          baseUrl.resolve('/v1/gateway/objects'),
          headers: {
            'content-type': 'application/json',
            'x-meshsetu-gateway-key': demoKey,
          },
          body: jsonEncode({
            'site_id': siteId,
            'object_id': objectId.toString(),
            'packet_b64': base64Encode(packet),
            'received_at_ms': receivedAtMs,
            'peer_id': peerId,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('dashboard packet HTTP ${response.statusCode}');
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
    'object_id': envelope.objectId.toString(),
    'site_id': envelope.siteId,
    'room_id': envelope.roomId,
    'priority': sos.triagePriority.name,
    'incident_type': sos.incidentType,
    'transcript': sos.transcript.isEmpty ? null : sos.transcript,
    'zone': sos.logicalZone.isEmpty ? null : sos.logicalZone,
    'latitude': sos.latitude,
    'longitude': sos.longitude,
    'accuracy_m': sos.accuracyM,
    'location_captured_at_ms': sos.locationCapturedAtMs,
    'hops': envelope.hopCount,
    'relay_latency_ms': relayLatencyMs,
    'voice_clip_id': sos.voiceClipId.isEmpty ? null : sos.voiceClipId,
    'audio_state': sos.voiceClipId.isEmpty ? null : 'queued',
    'reporter_uid': sos.reporter?.reporterUid,
    'reporter_name': sos.reporter?.name,
    'reporter_phone': sos.reporter?.phone,
    'reporter_language': sos.reporter?.language,
    'reporter_blood_group': sos.reporter?.bloodGroup,
    'reporter_primary_contact': sos.reporter == null
        ? null
        : '${sos.reporter!.primaryContactName} (${sos.reporter!.primaryContactPhone})',
  };

  Map<String, Object?> voiceCompleteJson(VoiceObjectPayload voice) => {
    'event_id': voice.sosEventId,
    'priority': 'unknown',
    'incident_type': 'unknown',
    'voice_clip_id': voice.clipId,
    'audio_state': 'complete',
  };

  Map<String, Object?> testSosJson(MeshEnvelope envelope) => {
    'event_id': envelope.eventId,
    'object_id': envelope.objectId.toString(),
    'site_id': envelope.siteId,
    'room_id': envelope.roomId,
    'priority': 'p0Critical',
    'incident_type': 'test_sos',
    'transcript': 'BLE SOS notification test',
    'hops': envelope.hopCount,
    'audio_state': 'n/a',
  };

  /// CEAL-style: register the onboarded user profile with the backend so
  /// UID→profile resolution works when only a compact BLE alert is received.
  Future<bool> registerProfile(Map<String, Object?> profile) async {
    try {
      final response = await http
          .post(
            baseUrl.resolve('/v1/profiles'),
            headers: {
              'content-type': 'application/json',
              'x-meshsetu-gateway-key': demoKey,
            },
            body: jsonEncode(profile),
          )
          .timeout(const Duration(seconds: 12));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Tests whether this phone can reach the configured control-room service.
  /// This is intentionally stronger than checking Wi-Fi/mobile-data state: a
  /// connected captive portal or a down control room cannot resolve an SOS.
  Future<bool> canReachControlRoom() async {
    try {
      final response = await http
          .get(baseUrl.resolve('/health'))
          .timeout(const Duration(seconds: 4));
      // Any non-server-error response proves the network path reached the
      // service, including a deployment-specific auth or route response.
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// CEAL-style: forward a compact BLE SOS alert (UID-only) to the backend
  /// so it can resolve the reporter's profile and create an enriched event.
  ///
  /// The decoded response body is returned so a receiver with internet can
  /// show the resolved incident detail instead of a generic alert.
  Future<(bool, String, Map<String, Object?>?)> forwardCealSos({
    required String reporterUid,
    required String siteId,
    required int flags,
    int? originId,
    int? sequence,
    double? latitude,
    double? longitude,
    double? accuracyM,
    int? locationCapturedAtMs,
  }) async {
    try {
      final response = await http
          .post(
            baseUrl.resolve('/v1/gateway/ceal-sos'),
            headers: {
              'content-type': 'application/json',
              'x-meshsetu-gateway-key': demoKey,
            },
            body: jsonEncode({
              'reporter_uid': reporterUid,
              'site_id': siteId,
              'flags': flags,
              'origin_id': originId,
              'sequence': sequence,
              'latitude': latitude,
              'longitude': longitude,
              'accuracy_m': accuracyM,
              'location_captured_at_ms': locationCapturedAtMs,
              'received_at_ms': DateTime.now().millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        return (
          true,
          'ok',
          decoded is Map ? decoded.cast<String, Object?>() : null,
        );
      }
      return (false, 'HTTP ${response.statusCode}: ${response.body}', null);
    } catch (error) {
      return (false, '$error', null);
    }
  }

  /// Fetches the incident record rendered by the dashboard for the native
  /// recipient detail screen. This public route is intentionally linked from
  /// SOS notifications and does not require operator credentials.
  Future<Map<String, Object?>?> fetchPublicIncident(String eventId) async {
    try {
      final response = await http
          .get(
            baseUrl.resolve('/v1/public/sos/${Uri.encodeComponent(eventId)}'),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Undelivered alerts addressed to this account (emergency-contact fan-out).
  Future<List<Map<String, Object?>>> fetchNotifications(
    String recipientUid,
  ) async {
    try {
      final response = await http
          .get(baseUrl.resolve('/v1/notifications/$recipientUid'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) item.cast<String, Object?>(),
      ];
    } catch (_) {
      return const [];
    }
  }
}

// The actual forwarding trigger lives in `app/mesh_bridge_client.dart`:
// `MeshTransportCoordinator.incoming` only exists in the background
// isolate, so the UI-isolate bridge client forwards `structuredSos`
// objects using this class's `postToDashboard`/`eventJson` as they arrive
// over the cross-isolate `mesh_received` channel.
