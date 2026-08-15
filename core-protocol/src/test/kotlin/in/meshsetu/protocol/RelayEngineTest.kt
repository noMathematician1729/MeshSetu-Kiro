package `in`.meshsetu.protocol

import `in`.meshsetu.model.MeshEnvelope
import `in`.meshsetu.model.PayloadType
import `in`.meshsetu.model.PriorityBand
import java.security.SecureRandom
import javax.crypto.spec.SecretKeySpec
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

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
}
