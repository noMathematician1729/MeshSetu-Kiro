package `in`.meshsetu.protocol

/**
 * Compact, non-identifying SOS metadata for BLE advertisements and relay state.
 *
 * This is intentionally separate from [MeshEnvelope]: it carries just enough to
 * identify and deduplicate an SOS before the encrypted object is available.
 * Layout: version(1), flags(1), pseudonymous UID(6), sequence(1), CRC-8(1).
 */
data class CompactSosAlert(
    val flags: UByte,
    val reporterUid: ByteArray,
    val sequence: UByte,
    val version: UByte = VERSION,
) {
    init {
        require(reporterUid.size == UID_BYTES) { "reporter UID must be $UID_BYTES bytes" }
        require(version == VERSION) { "unsupported compact SOS version: $version" }
    }

    fun isActive(): Boolean = flags.toInt() and FLAG_SOS_ACTIVE != 0
    fun isMedical(): Boolean = flags.toInt() and FLAG_MEDICAL_EMERGENCY != 0
    fun deduplicationKey(): String = reporterUid.joinToString("") { "%02x".format(it.toInt() and 0xff) } + ":${sequence.toInt()}"

    companion object {
        const val PACKET_BYTES = 10
        const val UID_BYTES = 6
        const val VERSION: UByte = 2u
        const val FLAG_SOS_ACTIVE = 1 shl 0
        const val FLAG_MEDICAL_EMERGENCY = 1 shl 1
    }
}

object CompactSosAlertCodec {
    fun encode(alert: CompactSosAlert): ByteArray = ByteArray(CompactSosAlert.PACKET_BYTES).also { out ->
        out[0] = alert.version.toByte()
        out[1] = alert.flags.toByte()
        alert.reporterUid.copyInto(out, destinationOffset = 2)
        out[8] = alert.sequence.toByte()
        out[9] = crc8(out, 0, 9).toByte()
    }

    /** Returns null for malformed, unknown-version, or CRC-invalid advertising data. */
    fun decodeOrNull(bytes: ByteArray): CompactSosAlert? {
        if (bytes.size != CompactSosAlert.PACKET_BYTES) return null
        if (bytes[0].toUByte() != CompactSosAlert.VERSION) return null
        if (bytes[9].toUByte() != crc8(bytes, 0, 9).toUByte()) return null
        return CompactSosAlert(
            flags = bytes[1].toUByte(),
            reporterUid = bytes.copyOfRange(2, 8),
            sequence = bytes[8].toUByte(),
        )
    }

    /** CRC-8/ATM: polynomial 0x07, initial value 0x00, no reflection. */
    private fun crc8(bytes: ByteArray, offset: Int, length: Int): Int {
        var crc = 0
        for (index in offset until offset + length) {
            crc = crc xor (bytes[index].toInt() and 0xff)
            repeat(8) { crc = if (crc and 0x80 != 0) (crc shl 1 xor 0x07) and 0xff else (crc shl 1) and 0xff }
        }
        return crc
    }
}
