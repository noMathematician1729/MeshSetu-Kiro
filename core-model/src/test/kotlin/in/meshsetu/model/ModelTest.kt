package `in`.meshsetu.model

import kotlin.test.Test
import kotlin.test.assertFailsWith

class ModelTest {
    @Test fun rejectsExpiredEnvelope() = assertFailsWith<IllegalArgumentException> {
        MeshEnvelope(1u, "e", "s", "r", 10, 10, 0, 1, PriorityBand.P0_CRITICAL, PayloadType.ACK, byteArrayOf(1), 2u)
    }
}
