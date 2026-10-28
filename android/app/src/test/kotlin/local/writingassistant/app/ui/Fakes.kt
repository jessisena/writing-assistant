package local.writingassistant.app.ui

import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.app.data.AppSettings
import local.writingassistant.core.Channel
import local.writingassistant.core.PolishResult
import local.writingassistant.core.Polishing
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
) : AppSettings {
    override suspend fun lastChannel(): Channel? = channel

    override suspend fun setLastChannel(channel: Channel) {
        this.channel = channel
    }
}

class FakeApiKeyStore(
    var key: String? = "sk-test",
) : ApiKeyStore {
    override suspend fun read(): String? = key

    override suspend fun write(key: String) {
        this.key = key
    }

    override suspend fun clear() {
        key = null
    }
}
