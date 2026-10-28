package local.writingassistant.app.data

/** Holds the user's Anthropic API key, encrypted at rest. Never log the key. */
interface ApiKeyStore {
    /** Returns the stored key, or null when none is set. */
    suspend fun read(): String?

    suspend fun write(key: String)

    suspend fun clear()
}
