package `in`.meshsetu.protocol

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CompactSosAlertTest {
    private val alert = CompactSosAlert(
        flags = (CompactSosAlert.FLAG_SOS_ACTIVE or CompactSosAlert.FLAG_MEDICAL_EMERGENCY).toUByte(),
        reporterUid = byteArrayOf(0x01, 0x23, 0x45, 0x67, 0x89.toByte(), 0xab.toByte()),
        sequence = 42u,
    )

    @Test fun `encodes CEAL compatible fixed 10 byte layout`() {
        val encoded = CompactSosAlertCodec.encode(alert)

        assertEquals(10, encoded.size)
        assertEquals(2, encoded[0].toInt())
        assertEquals(3, encoded[1].toInt())
        assertContentEquals(alert.reporterUid, encoded.copyOfRange(2, 8))
        assertEquals(42, encoded[8].toInt())
    }

    @Test fun `decodes a verified alert and derives relay-safe state`() {
        val decoded = assertNotNull(CompactSosAlertCodec.decodeOrNull(CompactSosAlertCodec.encode(alert)))

        assertEquals(alert.flags, decoded.flags)
        assertContentEquals(alert.reporterUid, decoded.reporterUid)
        assertEquals(alert.sequence, decoded.sequence)
        assertTrue(decoded.isActive())
        assertTrue(decoded.isMedical())
        assertEquals("0123456789ab:42", decoded.deduplicationKey())
    }

    @Test fun `encodes CEAL emergency types in flags bits two through five`() {
        val flags = CompactSosAlert.flagsFor(EmergencyType.FIRE)

        assertEquals(0b00000101u.toUByte(), flags)
        assertEquals(EmergencyType.FIRE, CompactSosAlert(flags, alert.reporterUid, 1u).emergencyType())
        assertEquals(EmergencyType.NATURAL_DISASTER, CompactSosAlert(0b00010101u.toUByte(), alert.reporterUid, 1u).emergencyType())
    }

    @Test fun `rejects corrupted packets and unsupported versions`() {
        val corrupted = CompactSosAlertCodec.encode(alert).also { it[4] = (it[4].toInt() xor 1).toByte() }
        val unsupported = CompactSosAlertCodec.encode(alert).also { it[0] = 1 }

        assertNull(CompactSosAlertCodec.decodeOrNull(corrupted))
        assertNull(CompactSosAlertCodec.decodeOrNull(unsupported))
        assertNull(CompactSosAlertCodec.decodeOrNull(ByteArray(9)))
        assertFalse(CompactSosAlert(flags = 0u, reporterUid = alert.reporterUid, sequence = 1u).isActive())
    }
}
