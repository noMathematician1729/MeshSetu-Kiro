package `in`.meshsetu.ble

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DiscoveryMetadataTest {
    @Test fun metadataRoundTripsAndRejectsWrongLength() {
        val source = DiscoveryMetadata(0x0102030405060708, 42u, 3u)
        assertEquals(source, DiscoveryMetadata.decode(source.encode()))
        assertNull(DiscoveryMetadata.decode(ByteArray(12)))
    }

    @Test fun connectionOwnerIsDeterministic() {
        assertTrue(shouldInitiate(1u, 2u))
        assertFalse(shouldInitiate(2u, 1u))
        assertFalse(shouldInitiate(3u, 3u))
    }
}

