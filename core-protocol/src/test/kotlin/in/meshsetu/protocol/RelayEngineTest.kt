package `in`.meshsetu.protocol

import `in`.meshsetu.model.MeshEnvelope
import `in`.meshsetu.model.EncryptedObject
import `in`.meshsetu.model.PayloadType
import `in`.meshsetu.model.PriorityBand
import java.security.SecureRandom
import javax.crypto.spec.SecretKeySpec
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertContentEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files

class RelayEngineTest {
    @Test fun persistsOnceAndEnqueuesNextHop() {
        val key = SecretKeySpec(ByteArray(32) { 7 }, "AES")
        val crypto = AeadEnvelope(key, SecureRandom())
        val stored = mutableListOf<MeshEnvelope>()
        val engine = MeshRelayEngine("site", crypto, object : RelayStore { override fun persist(value: MeshEnvelope) { stored.add(value) } }, { 100 })
        val source = MeshEnvelope(11u, "event", "site", "room", 1, 1_000, 0, 2, PriorityBand.P0_CRITICAL, PayloadType.STRUCTURED_SOS, byteArrayOf(9), 1u)
        val encrypted = crypto.encrypt(source)
        val frames = fragment(source.objectId, 1u, encrypted.bytes, 185).shuffled()
        val result = frames.fold(RelayResult(emptyList(), emptyList())) { _, frame -> engine.receive("a", FrameCodec.encode(frame)) }
        assertEquals(1, stored.size)
        assertTrue(result.controlFrames.isNotEmpty())
        assertEquals(1L, result.metrics.count { it.kind == "object_complete" }.toLong())
        assertEquals(11u, engine.nextOutbound(100)?.objectId)
    }

    @Test fun rejectsWrongSiteAndDuplicates() {
        val crypto = AeadEnvelope(SecretKeySpec(ByteArray(32) { 8 }, "AES"))
        val stored = mutableListOf<MeshEnvelope>()
        val engine = MeshRelayEngine("site", crypto, object : RelayStore { override fun persist(value: MeshEnvelope) { stored.add(value) } }, { 100 })
        val source = MeshEnvelope(12u, "event", "other", "room", 1, 1_000, 0, 2, PriorityBand.P0_CRITICAL, PayloadType.STRUCTURED_SOS, byteArrayOf(9), 1u)
        val blob = crypto.encrypt(source)
        val frame = FrameCodec.encode(fragment(source.objectId, 1u, blob.bytes, 185).single())
        assertTrue(engine.receive("a", frame).metrics.any { it.kind == "wrong_site" })
        assertTrue(stored.isEmpty())
    }

    @Test fun retainsOutboxUntilCustodyAckAndRetriesNack() {
        val crypto = AeadEnvelope(SecretKeySpec(ByteArray(32) { 3 }, "AES"))
        val acked = mutableListOf<ULong>()
        val store = object : RelayStore {
            override fun persist(value: MeshEnvelope) = Unit
            override fun markAck(objectId: ULong, peerId: String) { acked += objectId }
        }
        val engine = MeshRelayEngine("site", crypto, store, { 100 })
        val source = MeshEnvelope(13u, "event", "site", "room", 1, 1_000, 0, 2, PriorityBand.P0_CRITICAL, PayloadType.STRUCTURED_SOS, byteArrayOf(9), 1u)
        engine.submit(source)
        val outbound = engine.nextOutbound(100)!!
        engine.markSent(outbound, "peer")
        val nack = FrameCodec.encode(MeshFrame(FrameType.NACK, 1u, 0u, source.objectId, 0u, 1u, byteArrayOf(1)))
        engine.receive("peer", nack)
        assertEquals(source.objectId, engine.nextOutbound(100)?.objectId)
        engine.markSent(outbound, "peer")
        val ackPayload = ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(source.objectId.toLong()).array()
        val ack = FrameCodec.encode(MeshFrame(FrameType.CUSTODY_ACK, 1u, 0u, source.objectId, 0u, 1u, ackPayload))
        engine.receive("peer", ack)
        assertEquals(listOf(source.objectId), acked)
        assertNull(engine.nextOutbound(100))
    }

    @Test fun fileStoreRestoresPendingOutbox() {
        val directory = Files.createTempDirectory("meshsetu-relay").toFile()
        val first = FileRelayStore(directory)
        val value = EncryptedObject(14u, `in`.meshsetu.model.TrafficClass.SOS_STRUCTURED, byteArrayOf(1, 2), 1_000, 10)
        first.enqueue(value)
        val restored = FileRelayStore(directory).pending(100).single()
        assertEquals(value.objectId, restored.objectId)
        assertEquals(value.trafficClass, restored.trafficClass)
        assertContentEquals(value.bytes, restored.bytes)
        assertEquals(value.expiresAtMs, restored.expiresAtMs)
        assertEquals(value.createdAtMs, restored.createdAtMs)
        first.markAck(value.objectId, "peer")
        assertTrue(FileRelayStore(directory).pending(100).isEmpty())
    }
}
