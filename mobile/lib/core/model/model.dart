import 'dart:typed_data';

/// Port of `in.meshsetu.model` (Kotlin `core-model/Model.kt`).
///
/// Kotlin's `ULong` (64-bit unsigned) is represented here as Dart's native
/// `int` (64-bit signed on the VM/native targets). Object/ephemeral IDs are
/// random 64-bit values; this is a deliberate, documented deviation from the
/// Kotlin source rather than a full unsigned-64-bit emulation, since Dart has
/// no unsigned 64-bit integer type. Values are compared/hashed as opaque
/// 64-bit patterns, so this does not change correctness for equality, dedupe
/// or wire round-tripping (bit pattern is preserved through protobuf's fixed64
/// encoding either way).
enum PriorityBand {
  p0Critical(1),
  p1High(2),
  p2Normal(3),
  p3Bulk(4);

  const PriorityBand(this.rank);
  final int rank;
}

enum PayloadType {
  structuredSos,
  roomMessage,
  voiceManifest,
  voiceObject,
  ack,
  responderUpdate,
  beaconObservation,
}

enum InputMode { tap, text, voice }

enum TrafficClass {
  controlAck(0),
  sosStructured(1),
  authorityControl(2),
  voiceEvidence(3),
  roomMessage(4),
  telemetry(5);

  const TrafficClass(this.rank);
  final int rank;
}

class MeshEnvelope {
  MeshEnvelope({
    required this.objectId,
    required this.eventId,
    required this.siteId,
    required this.roomId,
    required this.createdAtMs,
    required this.expiresAtMs,
    required this.hopCount,
    required this.hopLimit,
    required this.priority,
    required this.payloadType,
    required this.payload,
    required this.originEphemeralId,
    Uint8List? traceId,
  }) : traceId = traceId ?? Uint8List(16) {
    if (objectId == 0) throw ArgumentError('objectId must not be 0');
    if (eventId.trim().isEmpty || siteId.trim().isEmpty) {
      throw ArgumentError('eventId and siteId must not be blank');
    }
    if (expiresAtMs <= createdAtMs) {
      throw ArgumentError('expiresAtMs must be after createdAtMs');
    }
    if (hopCount < 0 || hopCount > hopLimit) {
      throw ArgumentError('hopCount must be within 0..hopLimit');
    }
    if (payload.isEmpty) throw ArgumentError('payload must not be empty');
  }

  final int objectId;
  final String eventId;
  final String siteId;
  final String roomId;
  final int createdAtMs;
  final int expiresAtMs;
  final int hopCount;
  final int hopLimit;
  final PriorityBand priority;
  final PayloadType payloadType;
  final Uint8List payload;
  final int originEphemeralId;
  final Uint8List traceId;

  MeshEnvelope copyWith({int? hopCount}) => MeshEnvelope(
    objectId: objectId,
    eventId: eventId,
    siteId: siteId,
    roomId: roomId,
    createdAtMs: createdAtMs,
    expiresAtMs: expiresAtMs,
    hopCount: hopCount ?? this.hopCount,
    hopLimit: hopLimit,
    priority: priority,
    payloadType: payloadType,
    payload: payload,
    originEphemeralId: originEphemeralId,
    traceId: traceId,
  );
}

class EncryptedObject {
  const EncryptedObject({
    required this.objectId,
    required this.trafficClass,
    required this.bytes,
    required this.expiresAtMs,
    this.createdAtMs = 0,
  });

  final int objectId;
  final TrafficClass trafficClass;
  final Uint8List bytes;
  final int expiresAtMs;
  final int createdAtMs;
}

class ReceivedObject {
  const ReceivedObject({
    required this.envelope,
    required this.peerId,
    required this.receivedAtMs,
  });

  final MeshEnvelope envelope;
  final String peerId;
  final int receivedAtMs;
}

class PeerState {
  const PeerState({
    required this.peerId,
    required this.siteFingerprint,
    required this.connected,
    required this.mtu,
    required this.rssi,
    required this.queuedObjects,
    required this.lastSeenMs,
  });

  final String peerId;
  final int siteFingerprint;
  final bool connected;
  final int mtu;
  final int? rssi;
  final int queuedObjects;
  final int lastSeenMs;
}

class BeaconObservation {
  const BeaconObservation({
    required this.anchorId,
    required this.rssi,
    required this.observedAtMs,
  });

  final String anchorId;
  final int rssi;
  final int observedAtMs;
}

class ZoneAnchor {
  const ZoneAnchor({required this.anchorId, required this.logicalZone});

  final String anchorId;
  final String logicalZone;
}

class ZoneEstimate {
  const ZoneEstimate({
    required this.logicalZone,
    required this.anchorId,
    required this.rssi,
    required this.approximate,
    required this.uncertainty,
  });

  final String? logicalZone;
  final String? anchorId;
  final int? rssi;
  final bool approximate;
  final String uncertainty;
}

class ZoneResolver {
  ZoneResolver(this._anchors, {int freshnessMs = 10000})
    : _freshnessMs = freshnessMs;

  final Map<String, ZoneAnchor> _anchors;
  final int _freshnessMs;

  ZoneEstimate estimate(List<BeaconObservation> observations, int nowMs) {
    BeaconObservation? best;
    for (final o in observations) {
      final age = nowMs - o.observedAtMs;
      if (age < 0 || age > _freshnessMs) continue;
      if (!_anchors.containsKey(o.anchorId)) continue;
      if (best == null || o.rssi > best.rssi) best = o;
    }
    if (best == null) {
      return const ZoneEstimate(
        logicalZone: null,
        anchorId: null,
        rssi: null,
        approximate: true,
        uncertainty: 'unknown',
      );
    }

    // Matches the Kotlin source exactly: the "second best" search is not
    // freshness-filtered, only identity- and anchor-membership-filtered.
    int? second;
    for (final o in observations) {
      if (identical(o, best) || !_anchors.containsKey(o.anchorId)) continue;
      if (second == null || o.rssi > second) second = o.rssi;
    }

    final String uncertainty;
    if (second == null || best.rssi - second >= 8) {
      uncertainty = 'low';
    } else if (best.rssi - second >= 3) {
      uncertainty = 'medium';
    } else {
      uncertainty = 'high';
    }

    return ZoneEstimate(
      logicalZone: _anchors[best.anchorId]!.logicalZone,
      anchorId: best.anchorId,
      rssi: best.rssi,
      approximate: true,
      uncertainty: uncertainty,
    );
  }
}
