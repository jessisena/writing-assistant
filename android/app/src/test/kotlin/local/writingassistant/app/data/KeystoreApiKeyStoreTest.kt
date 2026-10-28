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
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.io.File
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
            assertNull(store.read())
        }

    @Test
    fun `a written key reads back`() =
        runTest {
            store.write(API_KEY)

            assertEquals(API_KEY, store.read())
        }

    @Test
    fun `a new write replaces the old key`() =
        runTest {
            store.write(API_KEY)
            store.write("sk-ant-second")

            assertEquals("sk-ant-second", store.read())
        }

    @Test
    fun `the key is not stored in plain text`() =
        runTest {
            store.write(API_KEY)

            val stored = storedValue()!!
            assertFalse(stored.contains(API_KEY))
            assertFalse(String(Base64.getDecoder().decode(stored)).contains(API_KEY))
        }

    @Test
    fun `clear removes the key`() =
        runTest {
            store.write(API_KEY)

            store.clear()

            assertNull(store.read())
            assertNull(storedValue())
        }

    @Test
    fun `clear on an empty store is a no-op`() =
        runTest {
            store.clear()

            assertNull(store.read())
        }

    @Test
    fun `a value that is not Base64 reads as no key and is cleared`() =
        runTest {
            putStoredValue("%%% not base64 %%%")

            assertNull(store.read())
            assertNull(storedValue())
        }

    @Test
    fun `a value shorter than the IV reads as no key and is cleared`() =
        runTest {
            putStoredValue(Base64.getEncoder().encodeToString(ByteArray(8)))

            assertNull(store.read())
            assertNull(storedValue())
        }

    @Test
    fun `tampered ciphertext reads as no key and is cleared`() =
        runTest {
            store.write(API_KEY)
            val bytes = Base64.getDecoder().decode(storedValue()!!)
            bytes[bytes.lastIndex] = (bytes.last().toInt() xor 0x01).toByte()
            putStoredValue(Base64.getEncoder().encodeToString(bytes))

            assertNull(store.read())
            assertNull(storedValue())
        }

    @Test
    fun `a value encrypted with a replaced device key reads as no key and is cleared`() =
        runTest {
            store.write(API_KEY)
            val replacedKey = newAesKey()

            val reopened = KeystoreApiKeyStore(dataStore) { replacedKey }

            assertNull(reopened.read())
            assertNull(storedValue())
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
