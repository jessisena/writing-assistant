package local.writingassistant.app.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.util.Base64
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private val Context.secretsDataStore by preferencesDataStore(name = "secrets")

/**
 * [ApiKeyStore] encrypting with an Android Keystore AES-GCM key, persisted in DataStore.
 *
 * The stored value is Base64 of the 12-byte IV followed by the ciphertext. A value that can no
 * longer be decrypted (for example after the Keystore key was invalidated) is cleared and read as
 * no key, so the user is asked to enter it again.
 */
class KeystoreApiKeyStore internal constructor(
    private val dataStore: DataStore<Preferences>,
    private val secretKey: () -> SecretKey,
) : ApiKeyStore {
    constructor(context: Context) : this(
        context.applicationContext.secretsDataStore,
        AndroidKeystoreKey::getOrCreate,
    )

    override suspend fun read(): String? {
        val stored = dataStore.data.first()[ENCRYPTED_KEY] ?: return null
        val key = withContext(Dispatchers.IO) { decryptOrNull(stored) }
        if (key == null) {
            dataStore.edit { if (it[ENCRYPTED_KEY] == stored) it.remove(ENCRYPTED_KEY) }
        }
        return key
    }

    override suspend fun write(key: String) {
        val encrypted = withContext(Dispatchers.IO) { encrypt(key) }
        dataStore.edit { it[ENCRYPTED_KEY] = encrypted }
    }

    override suspend fun clear() {
        dataStore.edit { it.remove(ENCRYPTED_KEY) }
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = cipher.iv
        check(iv.size == IV_LENGTH) { "Unexpected GCM IV length ${iv.size}" }
        return Base64.getEncoder().encodeToString(iv + cipher.doFinal(plain.toByteArray()))
    }

    private fun decryptOrNull(stored: String): String? =
        try {
            decrypt(Base64.getDecoder().decode(stored))
        } catch (e: GeneralSecurityException) {
            Log.w(TAG, "Stored API key can't be decrypted (${e.javaClass.simpleName}); clearing it")
            null
        } catch (e: IllegalArgumentException) {
            Log.w(
                TAG,
                "Stored API key is not valid Base64 (${e.javaClass.simpleName}); clearing it",
            )
            null
        }

    private fun decrypt(data: ByteArray): String {
        if (data.size <= IV_LENGTH) throw AEADBadTagException("Stored value is too short")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(TAG_LENGTH_BITS, data, 0, IV_LENGTH)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), spec)
        return String(cipher.doFinal(data, IV_LENGTH, data.size - IV_LENGTH))
    }

    private companion object {
        const val TAG = "KeystoreApiKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
        const val TAG_LENGTH_BITS = 128
        val ENCRYPTED_KEY = stringPreferencesKey("anthropic_api_key")
    }
}

private object AndroidKeystoreKey {
    private const val PROVIDER = "AndroidKeyStore"
    private const val ALIAS = "anthropic_api_key"
    private const val KEY_SIZE_BITS = 256

    @Synchronized
    fun getOrCreate(): SecretKey {
        val keyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }
        (keyStore.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val spec =
            KeyGenParameterSpec
                .Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(KEY_SIZE_BITS)
                .build()
        return KeyGenerator
            .getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
            .apply { init(spec) }
            .generateKey()
    }
}
