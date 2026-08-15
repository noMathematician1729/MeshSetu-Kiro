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
        val site = value.siteId.toByteArray(Charsets.UTF_8)
        require(site.size <= Short.MAX_VALUE.toInt()) { "site id is too long" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            updateAAD(aad(value.objectId, site))
        }
        val ciphertext = cipher.doFinal(EnvelopeCodec.encode(value))
        val blob = ByteBuffer.allocate(1 + 2 + site.size + IV_BYTES + ciphertext.size)
            .put(FORMAT_VERSION).putShort(site.size.toShort()).put(site).put(iv).put(ciphertext).array()
        return EncryptedObject(value.objectId, value.toTrafficClass(), blob, value.expiresAtMs, value.createdAtMs)
    }

    override fun decrypt(value: EncryptedObject): Result<MeshEnvelope> = runCatching {
        require(value.bytes.size > 1 + 2 + IV_BYTES + 16) { "encrypted object is too short" }
        val input = ByteBuffer.wrap(value.bytes).order(ByteOrder.BIG_ENDIAN)
        require(input.get() == FORMAT_VERSION) { "unsupported crypto format" }
        val siteLength = input.short.toInt()
        require(siteLength >= 0 && siteLength <= input.remaining()) { "invalid site metadata" }
        val site = ByteArray(siteLength).also(input::get)
        val iv = ByteArray(IV_BYTES).also(input::get)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            updateAAD(aad(value.objectId, site))
        }
        val plaintext = cipher.doFinal(ByteArray(input.remaining()).also(input::get))
        val envelope = EnvelopeCodec.decode(plaintext)
        require(envelope.objectId == value.objectId) { "object id mismatch" }
        require(envelope.siteId == site.toString(Charsets.UTF_8)) { "site id mismatch" }
        envelope
    }

    private fun aad(objectId: ULong, site: ByteArray): ByteArray = ByteBuffer.allocate(1 + 8 + 2 + site.size)
        .order(ByteOrder.BIG_ENDIAN).put(FORMAT_VERSION).putLong(objectId.toLong()).putShort(site.size.toShort()).put(site).array()
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
