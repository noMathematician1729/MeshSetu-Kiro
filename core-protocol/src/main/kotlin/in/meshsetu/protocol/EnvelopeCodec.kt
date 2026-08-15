package `in`.meshsetu.protocol

import `in`.meshsetu.model.MeshEnvelope as ModelEnvelope
import `in`.meshsetu.model.PayloadType as ModelPayloadType
import `in`.meshsetu.model.PriorityBand

object EnvelopeCodec {
    fun encode(value: ModelEnvelope): ByteArray = MeshEnvelope.newBuilder()
        .setObjectId(value.objectId.toLong()).setEventId(value.eventId).setSiteId(value.siteId).setRoomId(value.roomId)
        .setCreatedAtMs(value.createdAtMs).setExpiresAtMs(value.expiresAtMs).setHopCount(value.hopCount).setHopLimit(value.hopLimit)
        .setPriority(value.priority.toProto()).setPayloadType(value.payloadType.toProto()).setPayload(com.google.protobuf.ByteString.copyFrom(value.payload))
        .setOriginEphemeralId(value.originEphemeralId.toLong()).setTraceId(com.google.protobuf.ByteString.copyFrom(value.traceId)).build().toByteArray()

    fun decode(bytes: ByteArray): ModelEnvelope {
        val value = MeshEnvelope.parseFrom(bytes)
        return ModelEnvelope(value.objectId.toULong(), value.eventId, value.siteId, value.roomId, value.createdAtMs, value.expiresAtMs,
            value.hopCount, value.hopLimit, value.priority.toModel(), value.payloadType.toModel(), value.payload.toByteArray(), value.originEphemeralId.toULong(), value.traceId.toByteArray())
    }

    private fun PriorityBand.toProto() = when (this) { PriorityBand.P0_CRITICAL -> Priority.P0_CRITICAL; PriorityBand.P1_HIGH -> Priority.P1_HIGH; PriorityBand.P2_NORMAL -> Priority.P2_NORMAL; PriorityBand.P3_BULK -> Priority.P3_BULK }
    private fun Priority.toModel() = when (this) { Priority.P0_CRITICAL -> PriorityBand.P0_CRITICAL; Priority.P1_HIGH -> PriorityBand.P1_HIGH; Priority.P2_NORMAL -> PriorityBand.P2_NORMAL; Priority.P3_BULK, Priority.UNRECOGNIZED, Priority.P_UNSPECIFIED -> PriorityBand.P3_BULK }
    private fun ModelPayloadType.toProto() = PayloadType.valueOf(name)
    private fun PayloadType.toModel() = when (this) { PayloadType.STRUCTURED_SOS -> ModelPayloadType.STRUCTURED_SOS; PayloadType.ROOM_MESSAGE -> ModelPayloadType.ROOM_MESSAGE; PayloadType.VOICE_MANIFEST -> ModelPayloadType.VOICE_MANIFEST; PayloadType.VOICE_OBJECT -> ModelPayloadType.VOICE_OBJECT; PayloadType.ACK -> ModelPayloadType.ACK; PayloadType.RESPONDER_UPDATE -> ModelPayloadType.RESPONDER_UPDATE; PayloadType.BEACON_OBSERVATION -> ModelPayloadType.BEACON_OBSERVATION; else -> error("unsupported payload type") }
}
