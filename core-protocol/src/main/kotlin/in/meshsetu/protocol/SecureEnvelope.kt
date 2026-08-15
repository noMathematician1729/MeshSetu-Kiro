package `in`.meshsetu.protocol

import `in`.meshsetu.model.EncryptedObject
import `in`.meshsetu.model.MeshEnvelope
import `in`.meshsetu.model.TrafficClass
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private const val FORMAT_VERSION: Byte = 1
private const val IV_BYTES = 12
private const val TAG_BITS = 128

class AeadEnvelope(private val key: SecretKey, private val random: SecureRandom = SecureRandom()) : CryptoEnvelope {
    override fun encrypt(value: MeshEnvelope): EncryptedObject {
        val iv = ByteArray(IV_BYTES).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            updateAAD(aad(value))
        }
        val ciphertext = cipher.doFinal(EnvelopeCodec.encode(value))
        val blob = ByteBuffer.allocate(1 + IV_BYTES + ciphertext.size).put(FORMAT_VERSION).put(iv).put(ciphertext).array()
        return EncryptedObject(value.objectId, value.toTrafficClass(), blob, value.expiresAtMs)
    }

    override fun decrypt(value: EncryptedObject): Result<MeshEnvelope> = runCatching {
        require(value.bytes.size > 1 + IV_BYTES + 16) { "encrypted object is too short" }
        val input = ByteBuffer.wrap(value.bytes).order(ByteOrder.BIG_ENDIAN)
        require(input.get() == FORMAT_VERSION) { "unsupported crypto format" }
        val iv = ByteArray(IV_BYTES).also(input::get)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            updateAAD(aad(value.objectId))
        }
        val plaintext = cipher.doFinal(ByteArray(input.remaining()).also(input::get))
        val envelope = EnvelopeCodec.decode(plaintext)
        require(envelope.objectId == value.objectId) { "object id mismatch" }
        envelope
    }

    private fun aad(value: MeshEnvelope): ByteArray = aad(value.objectId)
    private fun aad(objectId: ULong): ByteArray = ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(objectId.toLong()).array()
}

private fun MeshEnvelope.toTrafficClass() = when (payloadType) {
    `in`.meshsetu.model.PayloadType.VOICE_OBJECT, `in`.meshsetu.model.PayloadType.VOICE_MANIFEST -> TrafficClass.VOICE_EVIDENCE
    `in`.meshsetu.model.PayloadType.ROOM_MESSAGE -> TrafficClass.ROOM_MESSAGE
    `in`.meshsetu.model.PayloadType.ACK -> TrafficClass.CONTROL_ACK
    `in`.meshsetu.model.PayloadType.RESPONDER_UPDATE -> TrafficClass.AUTHORITY_CONTROL
    `in`.meshsetu.model.PayloadType.BEACON_OBSERVATION -> TrafficClass.TELEMETRY
    `in`.meshsetu.model.PayloadType.STRUCTURED_SOS -> TrafficClass.SOS_STRUCTURED
}

interface CryptoEnvelope {
    fun encrypt(value: MeshEnvelope): EncryptedObject
    fun decrypt(value: EncryptedObject): Result<MeshEnvelope>
}
