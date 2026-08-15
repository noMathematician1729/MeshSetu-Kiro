package `in`.meshsetu.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

const val FRAME_HEADER_BYTES = 16
const val FRAME_VERSION: UByte = 1u
const val MAX_CHUNKS = 512
const val MAX_OBJECT_BYTES = 64 * 1024

enum class FrameType(val wire: UByte) { DATA(1u), HELLO(2u), CUSTODY_ACK(3u), NACK(4u), ERROR(5u) }

data class MeshFrame(
    val type: FrameType,
    val priority: UByte,
    val flags: UByte,
    val objectId: ULong,
    val sequence: UShort,
    val count: UShort,
    val payload: ByteArray,
)

object FrameCodec {
    fun encode(frame: MeshFrame): ByteArray {
        require(frame.priority <= 5u)
        require(frame.count.toInt() in 1..MAX_CHUNKS)
        require(frame.sequence < frame.count)
        require(frame.payload.size <= UShort.MAX_VALUE.toInt())
        return ByteBuffer.allocate(FRAME_HEADER_BYTES + frame.payload.size).order(ByteOrder.BIG_ENDIAN).apply {
            put(FRAME_VERSION.toByte()); put(frame.type.wire.toByte()); put(frame.priority.toByte()); put(frame.flags.toByte())
            putLong(frame.objectId.toLong()); putShort(frame.sequence.toShort()); putShort(frame.count.toShort()); put(frame.payload)
        }.array()
    }

    fun decode(bytes: ByteArray): MeshFrame {
        require(bytes.size >= FRAME_HEADER_BYTES) { "frame is shorter than header" }
        val input = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        require(input.get().toUByte() == FRAME_VERSION) { "unsupported frame version" }
        val type = FrameType.entries.firstOrNull { it.wire == input.get().toUByte() } ?: error("unknown frame type")
        val priority = input.get().toUByte().also { require(it <= 5u) }
        val flags = input.get().toUByte()
        val objectId = input.long.toULong().also { require(it != 0uL) }
        val sequence = input.short.toUShort()
        val count = input.short.toUShort().also { require(it.toInt() in 1..MAX_CHUNKS) }
        require(sequence < count) { "sequence outside chunk count" }
        return MeshFrame(type, priority, flags, objectId, sequence, count, ByteArray(input.remaining()).also(input::get))
    }
}

fun maxFragmentPayload(mtu: Int): Int = ((mtu - 3).coerceAtLeast(20) - FRAME_HEADER_BYTES).coerceAtLeast(1)

fun fragment(objectId: ULong, priority: UByte, encrypted: ByteArray, mtu: Int): List<MeshFrame> {
    require(objectId != 0uL)
    require(encrypted.isNotEmpty() && encrypted.size <= MAX_OBJECT_BYTES)
    val size = maxFragmentPayload(mtu)
    val count = (encrypted.size + size - 1) / size
    require(count in 1..MAX_CHUNKS) { "object requires too many chunks" }
    return List(count) { index ->
        val start = index * size
        MeshFrame(FrameType.DATA, priority, 0u, objectId, index.toUShort(), count.toUShort(), encrypted.copyOfRange(start, min(start + size, encrypted.size)))
    }
}

class ReassemblyBuffer(private val expectedCount: Int, private val maxBytes: Int = MAX_OBJECT_BYTES) {
    init { require(expectedCount in 1..MAX_CHUNKS) }
    private val parts = arrayOfNulls<ByteArray>(expectedCount)
    private var bytes = 0
    var received: Int = 0
        private set

    fun add(frame: MeshFrame): Boolean {
        if (frame.count.toInt() != expectedCount || frame.sequence.toInt() !in parts.indices || parts[frame.sequence.toInt()] != null) return false
        require(bytes + frame.payload.size <= maxBytes) { "reassembly exceeds limit" }
        parts[frame.sequence.toInt()] = frame.payload.copyOf()
        bytes += frame.payload.size
        received++
        return true
    }

    fun complete(): Boolean = received == expectedCount

    fun join(): ByteArray {
        check(complete()) { "object is incomplete" }
        return ByteArray(bytes).also { out ->
            var offset = 0
            parts.forEach { part -> part!!.copyInto(out, offset); offset += part.size }
        }
    }

    fun missingBitmap(): ByteArray = ByteArray((expectedCount + 7) / 8).also { out ->
        parts.forEachIndexed { index, part -> if (part == null) out[index / 8] = (out[index / 8].toInt() or (1 shl (index % 8))).toByte() }
    }
}
