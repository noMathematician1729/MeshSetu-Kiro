package `in`.meshsetu.protocol

import `in`.meshsetu.model.MeshEnvelope
import `in`.meshsetu.model.PayloadType
import `in`.meshsetu.model.PriorityBand
import java.util.Base64
import javax.crypto.spec.SecretKeySpec
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertContentEquals

class SecureEnvelopeTest {
    private val crypto = AeadEnvelope(SecretKeySpec(ByteArray(32) { it.toByte() }, "AES"))

    @Test fun authenticatedRoundTripAndTamperRejection() {
        val source = MeshEnvelope(8u, "event", "site", "room", 1, 2, 0, 5, PriorityBand.P0_CRITICAL, PayloadType.STRUCTURED_SOS, byteArrayOf(1), 9u)
        val encrypted = crypto.encrypt(source)
        val decoded = crypto.decrypt(encrypted).getOrThrow()
        assertEquals(source.objectId, decoded.objectId)
        assertEquals(source.eventId, decoded.eventId)
        assertContentEquals(source.payload, decoded.payload)
        val tampered = encrypted.copy(bytes = encrypted.bytes.copyOf().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() })
        assertTrue(crypto.decrypt(tampered).isFailure)
    }

    @Test fun siteMetadataIsAuthenticated() {
        val source = MeshEnvelope(9u, "event", "site", "room", 1, 2, 0, 5, PriorityBand.P0_CRITICAL, PayloadType.STRUCTURED_SOS, byteArrayOf(1), 9u)
        val encrypted = crypto.encrypt(source)
        val tampered = encrypted.copy(bytes = encrypted.bytes.copyOf().also { it[3] = 'x'.code.toByte() })
        assertTrue(crypto.decrypt(tampered).isFailure)
    }
}
