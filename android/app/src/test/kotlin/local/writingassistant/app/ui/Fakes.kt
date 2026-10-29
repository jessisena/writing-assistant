package local.writingassistant.app.ui

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.app.data.AppSettings
import local.writingassistant.app.data.HistoryRepository
import local.writingassistant.app.data.PalettePreset
import local.writingassistant.core.Channel
import local.writingassistant.core.HistoryStore
import local.writingassistant.core.PolishResult
import local.writingassistant.core.Polishing
import local.writingassistant.core.Provider
import local.writingassistant.core.Refinement
import java.nio.file.Files

/** [Polishing] whose answers are supplied by each test; records every call. */
class FakePolishing : Polishing {
    data class Call(
        val text: String,
        val channel: Channel,
        val refinement: Refinement? = null,
    )

    val calls = mutableListOf<Call>()

    /** The `learningSummary` argument of every [polish] call. */
    val learningSummaryRequests = mutableListOf<Boolean>()
    var onPolish: suspend (String) -> PolishResult = { result(it) }
    var onRefine: suspend (
        String,
        Refinement,
    ) -> String = { text, refinement -> "$text (${refinement.id})" }
    var onCheckReady: suspend () -> Unit = {}

    override suspend fun polish(
        text: String,
        channel: Channel,
        learningSummary: Boolean,
    ): PolishResult {
        calls += Call(text, channel)
        learningSummaryRequests += learningSummary
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
    override val disabledChannels = MutableStateFlow(emptySet<Channel>())
    override val learningSummaryEnabled = MutableStateFlow(true)
    override val palette = MutableStateFlow(PalettePreset.WRITING_DESK)

    override suspend fun setChannelEnabled(
        channel: Channel,
        enabled: Boolean,
    ) {
        disabledChannels.value =
            if (enabled) disabledChannels.value - channel else disabledChannels.value + channel
    }

    override suspend fun setLearningSummaryEnabled(enabled: Boolean) {
        learningSummaryEnabled.value = enabled
    }

    override suspend fun setPalette(palette: PalettePreset) {
        this.palette.value = palette
    }

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

/**
 * In-memory [ApiKeyStore]; [key] is the Anthropic key, the one most tests care about. A set
 * [readGate] or [writeGate] holds that operation until the test completes it, so a test can act
 * while it is in flight; completing it exceptionally makes the operation fail.
 */
class FakeApiKeyStore(
    key: String? = "sk-test",
) : ApiKeyStore {
    val keys = mutableMapOf<Provider, String>()
    var readGate: CompletableDeferred<Unit>? = null
    var writeGate: CompletableDeferred<Unit>? = null

    var key: String?
        get() = keys[Provider.ANTHROPIC]
        set(value) {
            if (value == null) keys.remove(Provider.ANTHROPIC) else keys[Provider.ANTHROPIC] = value
        }

    init {
        this.key = key
    }

    override suspend fun read(provider: Provider): String? {
        readGate?.await()
        return keys[provider]
    }

    override suspend fun write(
        provider: Provider,
        key: String,
    ) {
        writeGate?.await()
        keys[provider] = key
    }

    override suspend fun clear(provider: Provider) {
        keys.remove(provider)
    }
}

/** A history kept in a fresh temp directory, so tests never touch each other's files. */
fun testHistory(): HistoryRepository =
    HistoryRepository(
        HistoryStore(Files.createTempDirectory("history").resolve("history.json").toFile()),
    )
