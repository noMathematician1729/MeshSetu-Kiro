package `in`.meshsetu.ble

import android.content.Context
import android.util.Base64
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.KeyGenerator
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

object DeviceKeyStore {
    fun getOrCreate(alias: String = "meshsetu_device_wrap"): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
        return generator.generateKey()
    }

    fun getOrCreateSiteKey(context: Context, siteId: String, provisionedKey: ByteArray): SecretKey {
        require(provisionedKey.size == 16 || provisionedKey.size == 24 || provisionedKey.size == 32) { "site key must be AES-sized" }
        val digest = MessageDigest.getInstance("SHA-256").digest(siteId.toByteArray())
        val alias = "meshsetu_site_${digest.copyOfRange(0, 8).joinToString("") { "%02x".format(it) }}"
        val preferences = context.getSharedPreferences("meshsetu_keys", Context.MODE_PRIVATE)
        val stored = preferences.getString(alias, null)
        if (stored != null) return SecretKeySpec(unwrap(getOrCreate(), stored), "AES")
        val iv = ByteArray(12).also(SecureRandom()::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, getOrCreate(), GCMParameterSpec(128, iv))
        }
        val blob = iv + cipher.doFinal(provisionedKey)
        check(preferences.edit().putString(alias, Base64.encodeToString(blob, Base64.NO_WRAP)).commit()) { "could not persist site key" }
        return SecretKeySpec(provisionedKey.copyOf(), "AES")
    }

    private fun unwrap(wrappingKey: SecretKey, encoded: String): ByteArray {
        val blob = Base64.decode(encoded, Base64.NO_WRAP)
        require(blob.size > 12) { "stored site key is invalid" }
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, wrappingKey, GCMParameterSpec(128, blob.copyOfRange(0, 12)))
            doFinal(blob.copyOfRange(12, blob.size))
        }
    }
}

/** Development-only bootstrap; production provisioning must supply a signed manifest key. */
object SiteKeyProvisioning {
    fun demoKey(siteId: String): ByteArray = MessageDigest.getInstance("SHA-256")
        .digest("MeshSetu-demo-site-key-v1:$siteId".toByteArray(StandardCharsets.UTF_8))
}
