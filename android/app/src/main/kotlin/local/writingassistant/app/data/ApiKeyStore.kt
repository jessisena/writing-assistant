package local.writingassistant.app.data

import local.writingassistant.core.Provider

/**
 * Holds one API key per [Provider], encrypted at rest. Never log a key.
 *
 * Every method throws `PolishError.KeyStorageFailed` when the device's secure storage fails.
 */
interface ApiKeyStore {
    /** Returns [provider]'s stored key, or null when none is set. */
    suspend fun read(provider: Provider): String?

    /** Stores [key] for [provider], replacing any previous one. [key] must not be blank. */
    suspend fun write(
        provider: Provider,
        key: String,
    )

    suspend fun clear(provider: Provider)
}
