package `in`.meshsetu.model

import kotlin.test.Test
import kotlin.test.assertEquals

class ZoneResolverTest {
    @Test fun nearestFreshAnchorWinsAndMissingAnchorDegrades() {
        val resolver = ZoneResolver(mapOf("a" to ZoneAnchor("a", "Gate A"), "b" to ZoneAnchor("b", "Gate B")))
        assertEquals("Gate B", resolver.estimate(listOf(BeaconObservation("a", -80, 100), BeaconObservation("b", -50, 100)), 100).logicalZone)
        assertEquals("unknown", resolver.estimate(emptyList(), 100).uncertainty)
    }
}

