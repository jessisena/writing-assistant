package local.writingassistant.app.data

/**
 * Holds the user's Anthropic API key, encrypted at rest. Never log the key.
 *
 * Every method throws `PolishError.KeyStorageFailed` when the device's secure storage fails.
 */
interface ApiKeyStore {
    /** Returns the stored key, or null when none is set. */
    suspend fun read(): String?

    /** Stores [key], replacing any previous one. [key] must not be blank. */
    suspend fun write(key: String)

    suspend fun clear()
}
