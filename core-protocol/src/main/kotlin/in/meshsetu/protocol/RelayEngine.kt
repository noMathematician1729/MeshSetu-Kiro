package `in`.meshsetu.protocol

import `in`.meshsetu.model.EncryptedObject
import `in`.meshsetu.model.MeshEnvelope
import java.nio.ByteBuffer
import java.nio.ByteOrder

interface RelayStore {
    fun persist(envelope: MeshEnvelope)
}

data class RelayMetric(val kind: String, val objectId: ULong? = null, val peerId: String? = null, val value: Long? = null)

data class RelayResult(val controlFrames: List<ByteArray>, val metrics: List<RelayMetric>)

class MeshRelayEngine(
    private val siteId: String,
    private val crypto: CryptoEnvelope,
    private val store: RelayStore,
    private val clockMs: () -> Long,
    private val scheduler: OutboundScheduler = OutboundScheduler(),
    private val dedupe: RecentObjectCache = RecentObjectCache(),
    private val onPersist: (MeshEnvelope, String) -> Unit = { _, _ -> },
) {
    private data class Key(val peerId: String, val objectId: ULong)
    private val partial = mutableMapOf<Key, ReassemblyBuffer>()
    private val metrics = mutableListOf<RelayMetric>()
    private val listeners = mutableListOf<(MeshEnvelope, String) -> Unit>()

    @Synchronized fun addPersistListener(listener: (MeshEnvelope, String) -> Unit) { listeners += listener }

    @Synchronized
    fun receive(peerId: String, encodedFrame: ByteArray): RelayResult {
        val frame = runCatching { FrameCodec.decode(encodedFrame) }.getOrElse {
            metrics += RelayMetric("invalid_frame", peerId = peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        if (frame.type == FrameType.CUSTODY_ACK) {
            metrics += RelayMetric("ack", frame.objectId, peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        if (frame.type != FrameType.DATA) return RelayResult(emptyList(), drainMetrics())
        val key = Key(peerId, frame.objectId)
        val buffer = partial.getOrPut(key) { ReassemblyBuffer(frame.count.toInt()) }
        runCatching { buffer.add(frame) }.onFailure {
            partial.remove(key)
            metrics += RelayMetric("reassembly_rejected", frame.objectId, peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        if (!buffer.complete()) return RelayResult(emptyList(), drainMetrics())
        partial.remove(key)
        val encrypted = EncryptedObject(frame.objectId, trafficClass(frame.priority), buffer.join(), Long.MAX_VALUE)
        val envelope = crypto.decrypt(encrypted).getOrElse {
            metrics += RelayMetric("invalid_object", frame.objectId, peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        if (envelope.siteId != siteId) {
            metrics += RelayMetric("wrong_site", envelope.objectId, peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        val now = clockMs()
        if (envelope.expiresAtMs <= now) {
            metrics += RelayMetric("expired", envelope.objectId, peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        if (!dedupe.markIfNew(envelope.objectId, envelope.expiresAtMs, now)) {
            metrics += RelayMetric("duplicate", envelope.objectId, peerId)
            return RelayResult(listOf(ack(frame.objectId, frame.priority)), drainMetrics())
        }
        store.persist(envelope)
        onPersist(envelope, peerId)
        listeners.forEach { it(envelope, peerId) }
        metrics += RelayMetric("object_complete", envelope.objectId, peerId, envelope.hopCount.toLong())
        if (envelope.hopCount < envelope.hopLimit) {
            scheduler.enqueue(crypto.encrypt(envelope.copy(hopCount = envelope.hopCount + 1)), now)
            metrics += RelayMetric("relay_enqueued", envelope.objectId, peerId)
        }
        return RelayResult(listOf(ack(frame.objectId, frame.priority)), drainMetrics())
    }

    @Synchronized fun nextOutbound(nowMs: Long = clockMs()): EncryptedObject? = scheduler.next(nowMs)

    @Synchronized fun submit(envelope: MeshEnvelope, nowMs: Long = clockMs()): EncryptedObject {
        val encrypted = crypto.encrypt(envelope)
        scheduler.enqueue(encrypted, nowMs)
        return encrypted
    }

    private fun drainMetrics(): List<RelayMetric> = metrics.toList().also { metrics.clear() }
    private fun trafficClass(priority: UByte) = when (priority.toInt()) { 1 -> `in`.meshsetu.model.TrafficClass.SOS_STRUCTURED; 2 -> `in`.meshsetu.model.TrafficClass.AUTHORITY_CONTROL; 3 -> `in`.meshsetu.model.TrafficClass.ROOM_MESSAGE; else -> `in`.meshsetu.model.TrafficClass.TELEMETRY }
    private fun ack(objectId: ULong, priority: UByte): ByteArray = FrameCodec.encode(MeshFrame(FrameType.CUSTODY_ACK, priority, 0u, objectId, 0u, 1u, ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(objectId.toLong()).array()))
}
