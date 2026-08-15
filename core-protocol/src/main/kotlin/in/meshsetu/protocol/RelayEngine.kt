package `in`.meshsetu.protocol

import `in`.meshsetu.model.EncryptedObject
import `in`.meshsetu.model.MeshEnvelope
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

interface RelayStore {
    fun persist(envelope: MeshEnvelope)
    fun contains(objectId: ULong): Boolean = false
    fun enqueue(value: EncryptedObject) = Unit
    fun pending(nowMs: Long): List<EncryptedObject> = emptyList()
    fun markAck(objectId: ULong, peerId: String) = Unit
    fun markDeferred(value: EncryptedObject) = Unit
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
    private val partialCreatedAt = mutableMapOf<Key, Long>()
    private val lastNackAt = mutableMapOf<Key, Long>()
    private val metrics = mutableListOf<RelayMetric>()
    private val listeners = mutableListOf<(MeshEnvelope, String) -> Unit>()
    private val knownObjects = mutableMapOf<ULong, EncryptedObject>()
    private val inFlight = mutableMapOf<Key, Long>()
    private val acknowledged = mutableSetOf<ULong>()

    init {
        store.pending(clockMs()).forEach { value ->
            knownObjects[value.objectId] = value
            scheduler.enqueue(value, clockMs())
        }
    }

    @Synchronized fun addPersistListener(listener: (MeshEnvelope, String) -> Unit) { listeners += listener }

    @Synchronized
    fun receive(peerId: String, encodedFrame: ByteArray): RelayResult {
        cleanupPartial(clockMs())
        val frame = runCatching { FrameCodec.decode(encodedFrame) }.getOrElse {
            metrics += RelayMetric("invalid_frame", peerId = peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        if (frame.type == FrameType.CUSTODY_ACK) {
            if (frame.payload.size != 8 || ByteBuffer.wrap(frame.payload).order(ByteOrder.BIG_ENDIAN).long.toULong() != frame.objectId) {
                metrics += RelayMetric("invalid_ack", frame.objectId, peerId)
                return RelayResult(emptyList(), drainMetrics())
            }
            if (inFlight.remove(Key(peerId, frame.objectId)) != null) {
                acknowledged += frame.objectId
                store.markAck(frame.objectId, peerId)
                metrics += RelayMetric("ack", frame.objectId, peerId)
            } else {
                metrics += RelayMetric("unexpected_ack", frame.objectId, peerId)
            }
            return RelayResult(emptyList(), drainMetrics())
        }
        if (frame.type == FrameType.NACK) {
            if (frame.payload.isEmpty()) {
                metrics += RelayMetric("invalid_nack", frame.objectId, peerId)
            } else {
                knownObjects[frame.objectId]?.let { value ->
                    if (!acknowledged.contains(frame.objectId)) {
                        scheduler.enqueue(value, clockMs())
                        metrics += RelayMetric("nack_retry", frame.objectId, peerId)
                    }
                } ?: metrics.add(RelayMetric("unknown_nack", frame.objectId, peerId))
            }
            return RelayResult(emptyList(), drainMetrics())
        }
        if (frame.type == FrameType.HELLO) {
            metrics += RelayMetric("hello", peerId = peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        if (frame.type != FrameType.DATA) return RelayResult(emptyList(), drainMetrics())
        val key = Key(peerId, frame.objectId)
        val buffer = partial[key] ?: run {
            if (partial.size >= MAX_PARTIAL_OBJECTS) {
                metrics += RelayMetric("reassembly_capacity", frame.objectId, peerId)
                return RelayResult(emptyList(), drainMetrics())
            }
            ReassemblyBuffer(frame.count.toInt()).also {
                partial[key] = it
                partialCreatedAt[key] = clockMs()
            }
        }
        runCatching { buffer.add(frame) }.onFailure {
            partial.remove(key)
            partialCreatedAt.remove(key)
            lastNackAt.remove(key)
            metrics += RelayMetric("reassembly_rejected", frame.objectId, peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        if (!buffer.complete()) return RelayResult(emptyList(), drainMetrics())
        partial.remove(key)
        partialCreatedAt.remove(key)
        lastNackAt.remove(key)
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
        if (store.contains(envelope.objectId) || !dedupe.markIfNew(envelope.objectId, envelope.expiresAtMs, now)) {
            metrics += RelayMetric("duplicate", envelope.objectId, peerId)
            return RelayResult(listOf(ack(frame.objectId, frame.priority)), drainMetrics())
        }
        runCatching { store.persist(envelope) }.onFailure {
            metrics += RelayMetric("persist_failed", envelope.objectId, peerId)
            return RelayResult(emptyList(), drainMetrics())
        }
        onPersist(envelope, peerId)
        listeners.forEach { it(envelope, peerId) }
        metrics += RelayMetric("object_complete", envelope.objectId, peerId, envelope.hopCount.toLong())
        if (envelope.hopCount < envelope.hopLimit) {
            enqueue(crypto.encrypt(envelope.copy(hopCount = envelope.hopCount + 1)), now)
            metrics += RelayMetric("relay_enqueued", envelope.objectId, peerId)
        }
        return RelayResult(listOf(ack(frame.objectId, frame.priority)), drainMetrics())
    }

    @Synchronized fun nextOutbound(nowMs: Long = clockMs()): EncryptedObject? = scheduler.next(nowMs)

    @Synchronized fun requeue(value: EncryptedObject, nowMs: Long = clockMs()) = enqueue(value, nowMs)

    @Synchronized fun markSent(value: EncryptedObject, peerId: String, nowMs: Long = clockMs()) {
        knownObjects[value.objectId] = value
        inFlight[Key(peerId, value.objectId)] = nowMs
    }

    @Synchronized fun retryExpired(nowMs: Long = clockMs(), timeoutMs: Long = 8_000) {
        val due = inFlight.filterValues { nowMs - it >= timeoutMs }.keys.toList()
        due.forEach { key ->
            inFlight.remove(key)
            if (key.objectId !in acknowledged) knownObjects[key.objectId]?.let { enqueue(it, nowMs) }
            metrics += RelayMetric("ack_timeout", key.objectId, key.peerId)
        }
    }

    @Synchronized fun defer(value: EncryptedObject) {
        knownObjects.remove(value.objectId)
        store.markDeferred(value)
    }

    @Synchronized fun missing(peerId: String, objectId: ULong, priority: UByte): ByteArray? {
        val buffer = partial[Key(peerId, objectId)] ?: return null
        return FrameCodec.encode(MeshFrame(FrameType.NACK, priority, 0u, objectId, 0u, 1u, buffer.missingBitmap()))
    }

    @Synchronized fun missingForPeer(peerId: String, priority: UByte = 3u, nowMs: Long = clockMs()): List<ByteArray> = partial.keys
        .filter { it.peerId == peerId && nowMs - (partialCreatedAt[it] ?: nowMs) >= NACK_DELAY_MS }
        .mapNotNull { key ->
            if (nowMs - (lastNackAt[key] ?: Long.MIN_VALUE) < NACK_DELAY_MS) return@mapNotNull null
            lastNackAt[key] = nowMs
            missing(peerId, key.objectId, priority)
        }

    @Synchronized fun submit(envelope: MeshEnvelope, nowMs: Long = clockMs()): EncryptedObject {
        val encrypted = crypto.encrypt(envelope)
        enqueue(encrypted, nowMs)
        return encrypted
    }

    private fun enqueue(value: EncryptedObject, nowMs: Long) {
        knownObjects[value.objectId] = value
        store.enqueue(value)
        scheduler.enqueue(value, nowMs)
    }

    private fun cleanupPartial(nowMs: Long) {
        val expired = partialCreatedAt.filterValues { nowMs - it >= PARTIAL_TIMEOUT_MS }.keys.toList()
        expired.forEach {
            partial.remove(it)
            partialCreatedAt.remove(it)
            lastNackAt.remove(it)
            metrics += RelayMetric("reassembly_timeout", it.objectId, it.peerId)
        }
    }

    @Synchronized fun drainMetrics(): List<RelayMetric> = metrics.toList().also { metrics.clear() }
    private fun trafficClass(priority: UByte) = when (priority.toInt()) { 1 -> `in`.meshsetu.model.TrafficClass.SOS_STRUCTURED; 2 -> `in`.meshsetu.model.TrafficClass.AUTHORITY_CONTROL; 3 -> `in`.meshsetu.model.TrafficClass.VOICE_EVIDENCE; 4 -> `in`.meshsetu.model.TrafficClass.ROOM_MESSAGE; else -> `in`.meshsetu.model.TrafficClass.TELEMETRY }
    private fun ack(objectId: ULong, priority: UByte): ByteArray = FrameCodec.encode(MeshFrame(FrameType.CUSTODY_ACK, priority, 0u, objectId, 0u, 1u, ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(objectId.toLong()).array()))

    private companion object {
        const val MAX_PARTIAL_OBJECTS = 128
        const val PARTIAL_TIMEOUT_MS = 30_000L
        const val NACK_DELAY_MS = 2_000L
    }
}

class FileRelayStore(private val directory: File) : RelayStore {
    private val inbox = File(directory, "inbox")
    private val outbox = File(directory, "outbox")

    init { inbox.mkdirs(); outbox.mkdirs(); File(directory, "deferred").mkdirs() }

    @Synchronized override fun persist(envelope: MeshEnvelope) = writeAtomically(File(inbox, "${envelope.objectId}.bin")) { output ->
        output.write(EnvelopeCodec.encode(envelope))
    }

    @Synchronized override fun contains(objectId: ULong): Boolean = File(inbox, "${objectId}.bin").isFile

    @Synchronized override fun enqueue(value: EncryptedObject) = writeAtomically(File(outbox, "${value.objectId}.bin")) { output ->
        DataOutputStream(output).apply {
            writeLong(value.objectId.toLong())
            writeInt(value.trafficClass.rank)
            writeLong(value.expiresAtMs)
            writeLong(value.createdAtMs)
            writeInt(value.bytes.size)
            write(value.bytes)
            flush()
        }
    }

    @Synchronized override fun pending(nowMs: Long): List<EncryptedObject> = outbox.listFiles().orEmpty().mapNotNull { file ->
        runCatching {
            DataInputStream(FileInputStream(file)).use {
                val id = it.readLong().toULong()
                val rank = it.readInt()
                val traffic = `in`.meshsetu.model.TrafficClass.entries.first { value -> value.rank == rank }
                val expires = it.readLong()
                val created = it.readLong()
                val length = it.readInt()
                require(length in 1..MAX_OBJECT_BYTES)
                EncryptedObject(id, traffic, ByteArray(length).also(it::readFully), expires, created)
            }
        }.getOrNull()?.takeIf { it.expiresAtMs > nowMs }
    }

    @Synchronized override fun markAck(objectId: ULong, peerId: String) { File(outbox, "${objectId}.bin").delete() }

    @Synchronized override fun markDeferred(value: EncryptedObject) {
        File(outbox, "${value.objectId}.bin").delete()
        writeAtomically(File(directory, "deferred/${value.objectId}.bin")) { output -> output.write(value.bytes) }
    }

    private fun writeAtomically(target: File, write: (FileOutputStream) -> Unit) {
        val temp = File(target.parentFile, "${target.name}.tmp")
        FileOutputStream(temp).use { output -> write(output); output.fd.sync() }
        runCatching {
            Files.move(temp.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        }.getOrElse {
            Files.move(temp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }
}
