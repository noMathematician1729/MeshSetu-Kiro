import 'dart:convert';

import '../core/model/model.dart';
import '../core/protocol/relay_engine.dart';

/// JSON codec shared between the UI isolate (`feature/*` repositories,
/// `core/data`) and the `flutter_foreground_task` background isolate that
/// owns `MeshTransportCoordinator` (`app/mesh_event_controller.dart`). The
/// plugin's isolate channel only carries JSON-ish primitives, so this is
/// the wire format for outbound sends and inbound received-object/metric
/// notifications crossing that boundary.
abstract final class MeshBridge {
  static Map<String, Object?> envelopeToJson(MeshEnvelope e) => {
    'objectId': e.objectId,
    'eventId': e.eventId,
    'siteId': e.siteId,
    'roomId': e.roomId,
    'createdAtMs': e.createdAtMs,
    'expiresAtMs': e.expiresAtMs,
    'hopCount': e.hopCount,
    'hopLimit': e.hopLimit,
    'priority': e.priority.name,
    'payloadType': e.payloadType.name,
    'payload': base64Encode(e.payload),
    'originEphemeralId': e.originEphemeralId,
    'traceId': base64Encode(e.traceId),
  };

  static MeshEnvelope envelopeFromJson(Map<Object?, Object?> map) =>
      MeshEnvelope(
        objectId: map['objectId'] as int,
        eventId: map['eventId'] as String,
        siteId: map['siteId'] as String,
        roomId: map['roomId'] as String,
        createdAtMs: map['createdAtMs'] as int,
        expiresAtMs: map['expiresAtMs'] as int,
        hopCount: map['hopCount'] as int,
        hopLimit: map['hopLimit'] as int,
        priority: PriorityBand.values.byName(map['priority'] as String),
        payloadType: PayloadType.values.byName(map['payloadType'] as String),
        payload: base64Decode(map['payload'] as String),
        originEphemeralId: map['originEphemeralId'] as int,
        traceId: map['traceId'] == null
            ? null
            : base64Decode(map['traceId'] as String),
      );

  static Map<String, Object?> receivedToJson(ReceivedObject r) => {
    'envelope': envelopeToJson(r.envelope),
    'peerId': r.peerId,
    'receivedAtMs': r.receivedAtMs,
    'encryptedBytes': r.encryptedBytes == null
        ? null
        : base64Encode(r.encryptedBytes!),
  };

  static ReceivedObject receivedFromJson(Map<Object?, Object?> map) =>
      ReceivedObject(
        envelope: envelopeFromJson(map['envelope'] as Map<Object?, Object?>),
        peerId: map['peerId'] as String,
        receivedAtMs: map['receivedAtMs'] as int,
        encryptedBytes: map['encryptedBytes'] == null
            ? null
            : base64Decode(map['encryptedBytes'] as String),
      );

  static RelayMetric metricFromJson(Map<Object?, Object?> map) => RelayMetric(
    map['kind'] as String,
    objectId: map['objectId'] as int?,
    peerId: map['peerId'] as String?,
    value: map['value'] as int?,
    detail: map['detail'] as String?,
  );
}
