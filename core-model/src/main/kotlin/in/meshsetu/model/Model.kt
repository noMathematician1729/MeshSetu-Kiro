package `in`.meshsetu.model

enum class PriorityBand(val rank: Int) { P0_CRITICAL(1), P1_HIGH(2), P2_NORMAL(3), P3_BULK(4) }

enum class PayloadType { STRUCTURED_SOS, ROOM_MESSAGE, VOICE_MANIFEST, VOICE_OBJECT, ACK, RESPONDER_UPDATE, BEACON_OBSERVATION }

enum class InputMode { TAP, TEXT, VOICE }

enum class TrafficClass(val rank: Int) {
    CONTROL_ACK(0), SOS_STRUCTURED(1), AUTHORITY_CONTROL(2), VOICE_EVIDENCE(3), ROOM_MESSAGE(4), TELEMETRY(5)
}

data class MeshEnvelope(
    val objectId: ULong,
    val eventId: String,
    val siteId: String,
    val roomId: String,
    val createdAtMs: Long,
    val expiresAtMs: Long,
    val hopCount: Int,
    val hopLimit: Int,
    val priority: PriorityBand,
    val payloadType: PayloadType,
    val payload: ByteArray,
    val originEphemeralId: ULong,
    val traceId: ByteArray = ByteArray(16),
) {
    init {
        require(objectId != 0uL)
        require(eventId.isNotBlank() && siteId.isNotBlank())
        require(expiresAtMs > createdAtMs)
        require(hopCount in 0..hopLimit)
        require(payload.isNotEmpty())
    }
}

data class EncryptedObject(val objectId: ULong, val trafficClass: TrafficClass, val bytes: ByteArray, val expiresAtMs: Long)

data class ReceivedObject(val envelope: MeshEnvelope, val peerId: String, val receivedAtMs: Long)

data class PeerState(
    val peerId: String,
    val siteFingerprint: Long,
    val connected: Boolean,
    val mtu: Int,
    val rssi: Int?,
    val queuedObjects: Int,
    val lastSeenMs: Long,
)
