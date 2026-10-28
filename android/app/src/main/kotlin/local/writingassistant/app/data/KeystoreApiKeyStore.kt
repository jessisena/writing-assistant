package local.writingassistant.app.data

import android.content.Context

/** [ApiKeyStore] encrypting with an Android Keystore AES-GCM key, persisted in DataStore. */
class KeystoreApiKeyStore(
    private val context: Context,
) : ApiKeyStore {
    override suspend fun read(): String? = TODO("client worker ($context)")

    override suspend fun write(key: String): Unit = TODO("client worker")

    override suspend fun clear(): Unit = TODO("client worker")
}
