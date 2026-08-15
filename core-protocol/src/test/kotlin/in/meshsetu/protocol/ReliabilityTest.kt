package `in`.meshsetu.protocol

import java.io.StringWriter
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ReliabilityTest {
    @Test fun missingBitmapAndLossHookAreDeterministic() {
        val frames = fragment(1u, 1u, ByteArray(8) { it.toByte() }, 23)
        val buffer = ReassemblyBuffer(frames.size)
        buffer.add(frames[0])
        assertContentEquals(byteArrayOf(0b0000_0010), buffer.missingBitmap())
        val lossy = LossyFrameInterceptor(dropEvery = 2)
        lossy.apply(byteArrayOf(1)); assertNull(lossy.apply(byteArrayOf(1)))
    }

    @Test fun metricsAreSingleLineAndEscaped() {
        val output = StringWriter()
        JsonLineMetricSink(output).write(ProtocolMetric(1, peer = "abcdefghijklmnop", kind = "x\"y", detail = "line\nvalue"))
        assertEquals("{\"time_ms\":1,\"kind\":\"x\\\"y\",\"peer\":\"abcdefghijkl\",\"detail\":\"line\\nvalue\"}\n", output.toString())
    }
}
