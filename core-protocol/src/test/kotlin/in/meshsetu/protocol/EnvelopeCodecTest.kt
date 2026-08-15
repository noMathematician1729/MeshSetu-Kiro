package `in`.meshsetu.protocol

import `in`.meshsetu.model.MeshEnvelope
import `in`.meshsetu.model.PayloadType
import `in`.meshsetu.model.PriorityBand
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals

class EnvelopeCodecTest {
    @Test fun protobufRoundTrip() {
        val source = MeshEnvelope(7u, "event", "site", "room", 1, 2, 0, 5, PriorityBand.P0_CRITICAL, PayloadType.STRUCTURED_SOS, byteArrayOf(1, 2), 9u, byteArrayOf(3))
        val result = EnvelopeCodec.decode(EnvelopeCodec.encode(source))
        assertEquals(source.copy(payload = result.payload, traceId = result.traceId), result)
        assertContentEquals(source.payload, result.payload)
    }
}

