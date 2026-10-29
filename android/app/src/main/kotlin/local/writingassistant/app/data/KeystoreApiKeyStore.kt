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
import local.writingassistant.core.PolishError
import local.writingassistant.core.Provider
import java.io.IOException
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
 * One device key encrypts every provider's API key; each is stored under `<provider id>_api_key`,
 * so the Anthropic key keeps the `anthropic_api_key` name it had before providers existed.
 *
 * The stored value is Base64 of the 12-byte IV followed by the ciphertext. A value that can no
 * longer be decrypted (for example after the Keystore key was invalidated) is cleared and read as
 * no key, so the user is asked to enter it again. Any other Keystore, cipher or DataStore failure
 * is thrown as [PolishError.KeyStorageFailed], which names the failure but never the key.
 */
class KeystoreApiKeyStore internal constructor(
    private val dataStore: DataStore<Preferences>,
    private val secretKey: () -> SecretKey,
) : ApiKeyStore {
    constructor(context: Context) : this(
        context.applicationContext.secretsDataStore,
        AndroidKeystoreKey::getOrCreate,
    )

    /** @throws PolishError.KeyStorageFailed when the Keystore or DataStore can't be used. */
    override suspend fun read(provider: Provider): String? =
        storageGuarded {
            val name = preferenceFor(provider)
            val stored = dataStore.data.first()[name] ?: return@storageGuarded null
            val key = withContext(Dispatchers.IO) { decryptOrNull(stored) }
            if (key == null) {
                dataStore.edit { if (it[name] == stored) it.remove(name) }
            }
            key
        }

    /**
     * Encrypts and stores [key], replacing any previous one.
     *
     * @throws IllegalArgumentException when [key] is blank; callers validate it first.
     * @throws PolishError.KeyStorageFailed when the Keystore or DataStore can't be used.
     */
    override suspend fun write(
        provider: Provider,
        key: String,
    ) {
        require(key.isNotBlank()) { "API key must not be blank" }
        storageGuarded {
            val encrypted = withContext(Dispatchers.IO) { cryptoGuarded { encrypt(key) } }
            dataStore.edit { it[preferenceFor(provider)] = encrypted }
        }
    }

    /** @throws PolishError.KeyStorageFailed when DataStore can't be written. */
    override suspend fun clear(provider: Provider) {
        storageGuarded { dataStore.edit { it.remove(preferenceFor(provider)) } }
    }

    private suspend fun <T> storageGuarded(body: suspend () -> T): T =
        try {
            body()
        } catch (e: IOException) {
            throw storageFailed(e)
        }

    private fun <T> cryptoGuarded(body: () -> T): T =
        try {
            body()
        } catch (e: Exception) {
            throw storageFailed(e)
        }

    private fun storageFailed(e: Exception): PolishError.KeyStorageFailed {
        val detail = e.javaClass.simpleName
        Log.w(TAG, "Secure key storage failed ($detail)")
        return PolishError.KeyStorageFailed(detail)
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = cipher.iv
        check(iv.size == IV_LENGTH) { "Unexpected GCM IV length ${iv.size}" }
        return Base64.getEncoder().encodeToString(iv + cipher.doFinal(plain.toByteArray()))
    }

    /**
     * Returns the decrypted key, or null when the stored value is unusable and should be cleared.
     * A device key that can't be loaded, or a Keystore runtime failure, is a storage failure
     * instead, so a transient error doesn't delete the user's key.
     */
    private fun decryptOrNull(stored: String): String? {
        val deviceKey = cryptoGuarded { secretKey() }
        return cryptoGuarded { decryptOrNull(stored, deviceKey) }
    }

    private fun decryptOrNull(
        stored: String,
        deviceKey: SecretKey,
    ): String? =
        try {
            decrypt(Base64.getDecoder().decode(stored), deviceKey)
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

    private fun decrypt(
        data: ByteArray,
        deviceKey: SecretKey,
    ): String {
        if (data.size <= IV_LENGTH) throw AEADBadTagException("Stored value is too short")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(TAG_LENGTH_BITS, data, 0, IV_LENGTH)
        cipher.init(Cipher.DECRYPT_MODE, deviceKey, spec)
        return String(cipher.doFinal(data, IV_LENGTH, data.size - IV_LENGTH))
    }

    private companion object {
        const val TAG = "KeystoreApiKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
        const val TAG_LENGTH_BITS = 128

        fun preferenceFor(provider: Provider) = stringPreferencesKey("${provider.id}_api_key")
    }
}

private object AndroidKeystoreKey {
    private const val PROVIDER = "AndroidKeyStore"

    // Encrypts every provider's key despite the name. Never rename it: keys already stored
    // under the old alias could no longer be decrypted.
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
