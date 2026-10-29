package local.writingassistant.app.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import local.writingassistant.core.PolishError
import local.writingassistant.core.Provider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.io.File
import java.security.ProviderException
import java.util.Base64
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

@RunWith(AndroidJUnit4::class)
@Config(sdk = [36])
class KeystoreApiKeyStoreTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val dataStore: DataStore<Preferences> by lazy {
        PreferenceDataStoreFactory.create(
            scope = scope,
        ) { File(folder.root, "secrets.preferences_pb") }
    }
    private val deviceKey = newAesKey()
    private val store by lazy { KeystoreApiKeyStore(dataStore) { deviceKey } }

    @After
    fun tearDown() {
        scope.cancel()
    }

    @Test
    fun `an empty store has no key`() =
        runTest {
            assertNull(store.read(Provider.ANTHROPIC))
        }

    @Test
    fun `a written key reads back`() =
        runTest {
            store.write(Provider.ANTHROPIC, API_KEY)

            assertEquals(API_KEY, store.read(Provider.ANTHROPIC))
        }

    @Test
    fun `a new write replaces the old key`() =
        runTest {
            store.write(Provider.ANTHROPIC, API_KEY)
            store.write(Provider.ANTHROPIC, "sk-ant-second")

            assertEquals("sk-ant-second", store.read(Provider.ANTHROPIC))
        }

    @Test
    fun `the key is not stored in plain text`() =
        runTest {
            store.write(Provider.ANTHROPIC, API_KEY)

            val stored = storedValue()!!
            assertFalse(stored.contains(API_KEY))
            assertFalse(String(Base64.getDecoder().decode(stored)).contains(API_KEY))
        }

    @Test
    fun `clear removes the key`() =
        runTest {
            store.write(Provider.ANTHROPIC, API_KEY)

            store.clear(Provider.ANTHROPIC)

            assertNull(store.read(Provider.ANTHROPIC))
            assertNull(storedValue())
        }

    @Test
    fun `clear on an empty store is a no-op`() =
        runTest {
            store.clear(Provider.ANTHROPIC)

            assertNull(store.read(Provider.ANTHROPIC))
        }

    @Test
    fun `a value that is not Base64 reads as no key and is cleared`() =
        runTest {
            putStoredValue("%%% not base64 %%%")

            assertNull(store.read(Provider.ANTHROPIC))
            assertNull(storedValue())
        }

    @Test
    fun `a value shorter than the IV reads as no key and is cleared`() =
        runTest {
            putStoredValue(Base64.getEncoder().encodeToString(ByteArray(8)))

            assertNull(store.read(Provider.ANTHROPIC))
            assertNull(storedValue())
        }

    @Test
    fun `tampered ciphertext reads as no key and is cleared`() =
        runTest {
            store.write(Provider.ANTHROPIC, API_KEY)
            val bytes = Base64.getDecoder().decode(storedValue()!!)
            bytes[bytes.lastIndex] = (bytes.last().toInt() xor 0x01).toByte()
            putStoredValue(Base64.getEncoder().encodeToString(bytes))

            assertNull(store.read(Provider.ANTHROPIC))
            assertNull(storedValue())
        }

    @Test
    fun `a value encrypted with a replaced device key reads as no key and is cleared`() =
        runTest {
            store.write(Provider.ANTHROPIC, API_KEY)
            val replacedKey = newAesKey()

            val reopened = KeystoreApiKeyStore(dataStore) { replacedKey }

            assertNull(reopened.read(Provider.ANTHROPIC))
            assertNull(storedValue())
        }

    @Test
    fun `a Keystore failure while encrypting is a key storage error and stores nothing`() =
        runTest {
            val failing = KeystoreApiKeyStore(dataStore) { throw ProviderException("boom") }

            val error = storageError { failing.write(Provider.ANTHROPIC, API_KEY) }

            assertEquals(PolishError.KeyStorageFailed("ProviderException"), error)
            assertNull(storedValue())
        }

    @Test
    fun `a Keystore failure while decrypting is a key storage error and keeps the key`() =
        runTest {
            store.write(Provider.ANTHROPIC, API_KEY)
            val stored = storedValue()
            val failing = KeystoreApiKeyStore(dataStore) { throw ProviderException("boom") }

            storageError { failing.read(Provider.ANTHROPIC) }

            assertEquals(stored, storedValue())
            assertEquals(API_KEY, store.read(Provider.ANTHROPIC))
        }

    @Test
    fun `a cipher runtime failure while decrypting is a key storage error`() =
        runTest {
            store.write(Provider.ANTHROPIC, API_KEY)
            val broken =
                object : SecretKey {
                    override fun getAlgorithm() = "AES"

                    override fun getFormat() = "RAW"

                    override fun getEncoded(): ByteArray = throw ProviderException("Keystore busy")
                }
            val failing = KeystoreApiKeyStore(dataStore) { broken }

            storageError { failing.read(Provider.ANTHROPIC) }

            assertEquals(API_KEY, store.read(Provider.ANTHROPIC))
        }

    @Test
    fun `writing a blank key is rejected`() =
        runTest {
            val error = runCatching { store.write(Provider.ANTHROPIC, " ") }.exceptionOrNull()

            assertTrue(error is IllegalArgumentException)
            assertNull(storedValue())
        }

    private suspend fun storageError(body: suspend () -> Unit): PolishError.KeyStorageFailed {
        try {
            body()
        } catch (e: PolishError.KeyStorageFailed) {
            assertFalse(e.toString().contains(API_KEY))
            return e
        }
        fail("Expected KeyStorageFailed")
        error("unreachable")
    }

    private suspend fun storedValue(): String? = dataStore.data.first()[STORED]

    private suspend fun putStoredValue(value: String) {
        dataStore.edit { it[STORED] = value }
    }

    private companion object {
        const val API_KEY = "sk-ant-api03-test-secret-key"
        val STORED = stringPreferencesKey("anthropic_api_key")

        fun newAesKey(): SecretKey =
            KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
    }
}
