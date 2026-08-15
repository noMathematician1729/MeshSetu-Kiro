import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import '../generated/meshsetu.pb.dart' as pb;
import '../model/model.dart' as model;

/// Port of `in.meshsetu.protocol.EnvelopeCodec` (Kotlin `EnvelopeCodec.kt`).
abstract final class EnvelopeCodec {
  static Uint8List encode(model.MeshEnvelope value) {
    final message = pb.MeshEnvelope(
      objectId: Int64(value.objectId),
      eventId: value.eventId,
      siteId: value.siteId,
      roomId: value.roomId,
      createdAtMs: Int64(value.createdAtMs),
      expiresAtMs: Int64(value.expiresAtMs),
      hopCount: value.hopCount,
      hopLimit: value.hopLimit,
      priority: _priorityToProto(value.priority),
      payloadType: _payloadTypeToProto(value.payloadType),
      payload: value.payload,
      originEphemeralId: Int64(value.originEphemeralId),
      traceId: value.traceId,
    );
    return Uint8List.fromList(message.writeToBuffer());
  }

  static model.MeshEnvelope decode(Uint8List bytes) {
    final value = pb.MeshEnvelope.fromBuffer(bytes);
    return model.MeshEnvelope(
      objectId: value.objectId.toInt(),
      eventId: value.eventId,
      siteId: value.siteId,
      roomId: value.roomId,
      createdAtMs: value.createdAtMs.toInt(),
      expiresAtMs: value.expiresAtMs.toInt(),
      hopCount: value.hopCount,
      hopLimit: value.hopLimit,
      priority: _priorityToModel(value.priority),
      payloadType: _payloadTypeToModel(value.payloadType),
      payload: Uint8List.fromList(value.payload),
      originEphemeralId: value.originEphemeralId.toInt(),
      traceId: Uint8List.fromList(value.traceId),
    );
  }

  static pb.Priority _priorityToProto(model.PriorityBand value) =>
      switch (value) {
        model.PriorityBand.p0Critical => pb.Priority.P0_CRITICAL,
        model.PriorityBand.p1High => pb.Priority.P1_HIGH,
        model.PriorityBand.p2Normal => pb.Priority.P2_NORMAL,
        model.PriorityBand.p3Bulk => pb.Priority.P3_BULK,
      };

  // Matches the Kotlin fallback: any unrecognized/unspecified wire value
  // degrades to the lowest-priority band rather than throwing.
  static model.PriorityBand _priorityToModel(pb.Priority value) =>
      switch (value) {
        pb.Priority.P0_CRITICAL => model.PriorityBand.p0Critical,
        pb.Priority.P1_HIGH => model.PriorityBand.p1High,
        pb.Priority.P2_NORMAL => model.PriorityBand.p2Normal,
        _ => model.PriorityBand.p3Bulk,
      };

  static pb.PayloadType _payloadTypeToProto(model.PayloadType value) =>
      switch (value) {
        model.PayloadType.structuredSos => pb.PayloadType.STRUCTURED_SOS,
        model.PayloadType.roomMessage => pb.PayloadType.ROOM_MESSAGE,
        model.PayloadType.voiceManifest => pb.PayloadType.VOICE_MANIFEST,
        model.PayloadType.voiceObject => pb.PayloadType.VOICE_OBJECT,
        model.PayloadType.ack => pb.PayloadType.ACK,
        model.PayloadType.responderUpdate => pb.PayloadType.RESPONDER_UPDATE,
        model.PayloadType.beaconObservation =>
          pb.PayloadType.BEACON_OBSERVATION,
      };

  static model.PayloadType _payloadTypeToModel(pb.PayloadType value) =>
      switch (value) {
        pb.PayloadType.STRUCTURED_SOS => model.PayloadType.structuredSos,
        pb.PayloadType.ROOM_MESSAGE => model.PayloadType.roomMessage,
        pb.PayloadType.VOICE_MANIFEST => model.PayloadType.voiceManifest,
        pb.PayloadType.VOICE_OBJECT => model.PayloadType.voiceObject,
        pb.PayloadType.ACK => model.PayloadType.ack,
        pb.PayloadType.RESPONDER_UPDATE => model.PayloadType.responderUpdate,
        pb.PayloadType.BEACON_OBSERVATION =>
          model.PayloadType.beaconObservation,
        _ => throw StateError('unsupported payload type'),
      };
}
