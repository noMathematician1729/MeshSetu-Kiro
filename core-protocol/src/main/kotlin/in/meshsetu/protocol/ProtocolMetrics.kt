package `in`.meshsetu.protocol

import java.io.Writer

data class ProtocolMetric(val timeMs: Long, val eventId: String? = null, val peer: String? = null, val kind: String, val value: Long? = null, val detail: String? = null)

class JsonLineMetricSink(private val writer: Writer) {
    @Synchronized fun write(metric: ProtocolMetric) {
        fun quote(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
        val fields = mutableListOf("\"time_ms\":${metric.timeMs}", "\"kind\":${quote(metric.kind)}")
        metric.eventId?.let { fields += "\"event_id\":${quote(it)}" }
        metric.peer?.let { fields += "\"peer\":${quote(it.take(12))}" }
        metric.value?.let { fields += "\"value\":$it" }
        metric.detail?.let { fields += "\"detail\":${quote(it)}" }
        writer.append("{").append(fields.joinToString(",")).append("}\n").flush()
    }
}

class LossyFrameInterceptor(private val dropEvery: Int = 0, private val corruptEvery: Int = 0) {
    private var count = 0
    fun apply(frame: ByteArray): ByteArray? {
        count++
        if (dropEvery > 0 && count % dropEvery == 0) return null
        if (corruptEvery > 0 && count % corruptEvery == 0) return frame.copyOf().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() }
        return frame
    }
}

