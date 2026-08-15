package `in`.meshsetu.protocol

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class FrameTest {
    @Test fun fragmentationRoundTripsAtAllMtuSizes() {
        val bytes = ByteArray(10_000) { (it % 251).toByte() }
        listOf(23, 100, 185, 247, 517).forEach { mtu ->
            val source = if (mtu == 23) bytes.copyOf(1_500) else bytes
            val frames = fragment(42u, 1u, source, mtu)
            val buffer = ReassemblyBuffer(frames.size)
            frames.shuffled().forEach { buffer.add(FrameCodec.decode(FrameCodec.encode(it))) }
            assertTrue(buffer.complete()); assertContentEquals(source, buffer.join())
        }
    }

    @Test fun malformedFramesFailBeforeUse() {
        assertFailsWith<IllegalArgumentException> { FrameCodec.decode(ByteArray(15)) }
        assertFailsWith<IllegalArgumentException> { FrameCodec.decode(ByteArray(16).also { it[0] = 9 }) }
    }

    @Test fun duplicateChunksAreIgnored() {
        val frame = fragment(42u, 1u, byteArrayOf(1, 2, 3), 23).single()
        val buffer = ReassemblyBuffer(1)
        assertEquals(true, buffer.add(frame)); assertEquals(false, buffer.add(frame)); assertEquals(1, buffer.received)
    }
}
