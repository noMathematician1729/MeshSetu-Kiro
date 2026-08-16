package `in`.meshsetu.app

/** Isolated one-packet transport smoke test, separate from production SOS. */
object TestSosPacket {
    const val MESSAGE = "TEST SOS RECEIVED: MeshSetu emergency link is working."
    private const val PAYLOAD_LENGTH = 100

    fun payload(): ByteArray {
        val message = MESSAGE.toByteArray(Charsets.UTF_8)
        check(message.size <= PAYLOAD_LENGTH) { "test SOS message exceeds 100-byte payload" }
        return ByteArray(PAYLOAD_LENGTH) { ' '.code.toByte() }.also {
            message.copyInto(it)
        }
    }
}
