package local.writingassistant.app.ui

import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.app.data.AppSettings
import local.writingassistant.core.Channel
import local.writingassistant.core.PolishResult
import local.writingassistant.core.Polishing
import local.writingassistant.core.Provider
import local.writingassistant.core.Refinement

/** [Polishing] whose answers are supplied by each test; records every call. */
class FakePolishing : Polishing {
    data class Call(
        val text: String,
        val channel: Channel,
        val refinement: Refinement? = null,
    )

    val calls = mutableListOf<Call>()
    var onPolish: suspend (String) -> PolishResult = { result(it) }
    var onRefine: suspend (
        String,
        Refinement,
    ) -> String = { text, refinement -> "$text (${refinement.id})" }
    var onCheckReady: suspend () -> Unit = {}

    override suspend fun polish(
        text: String,
        channel: Channel,
    ): PolishResult {
        calls += Call(text, channel)
        return onPolish(text)
    }

    override suspend fun refine(
        text: String,
        channel: Channel,
        refinement: Refinement,
    ): String {
        calls += Call(text, channel, refinement)
        return onRefine(text, refinement)
    }

    override suspend fun checkReady() = onCheckReady()

    companion object {
        fun result(text: String) =
            PolishResult(
                polishedText = "polished: $text",
                learningSummary = null,
                detectedLanguage = "en",
                wasTranslated = false,
                modelUsed = "fake",
            )
    }
}

class FakeAppSettings(
    var channel: Channel? = null,
    var provider: Provider = Provider.ANTHROPIC,
) : AppSettings {
    override suspend fun lastChannel(): Channel? = channel

    override suspend fun setLastChannel(channel: Channel) {
        this.channel = channel
    }

    override suspend fun provider(): Provider = provider

    override suspend fun setProvider(provider: Provider) {
        this.provider = provider
    }
}

/** [ApiKeyStore] whose every operation fails with [error]. */
class FailingKeyStore(
    private val error: Exception,
) : ApiKeyStore {
    override suspend fun read(provider: Provider): String? = throw error

    override suspend fun write(
        provider: Provider,
        key: String,
    ) = throw error

    override suspend fun clear(provider: Provider) = throw error
}

/** In-memory [ApiKeyStore]; [key] is the Anthropic key, the one most tests care about. */
class FakeApiKeyStore(
    key: String? = "sk-test",
) : ApiKeyStore {
    val keys = mutableMapOf<Provider, String>()

    var key: String?
        get() = keys[Provider.ANTHROPIC]
        set(value) {
            if (value == null) keys.remove(Provider.ANTHROPIC) else keys[Provider.ANTHROPIC] = value
        }

    init {
        this.key = key
    }

    override suspend fun read(provider: Provider): String? = keys[provider]

    override suspend fun write(
        provider: Provider,
        key: String,
    ) {
        keys[provider] = key
    }

    override suspend fun clear(provider: Provider) {
        keys.remove(provider)
    }
}
