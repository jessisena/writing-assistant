package local.writingassistant.app.ui

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.app.data.AppSettings
import local.writingassistant.app.data.HistoryRepository
import local.writingassistant.app.data.ModeProfile
import local.writingassistant.app.data.ModeSettings
import local.writingassistant.app.data.PalettePreset
import local.writingassistant.core.Channel
import local.writingassistant.core.HistoryEntry
import local.writingassistant.core.HistoryStore
import local.writingassistant.core.Mode
import local.writingassistant.core.OutputLanguage
import local.writingassistant.core.PolishOptions
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

    /** The `options` argument of every [polish] call. */
    val requestedOptions = mutableListOf<PolishOptions>()
    var onPolish: suspend (String) -> PolishResult = { result(it) }
    var onRefine: suspend (
        String,
        Refinement,
    ) -> String = { text, refinement -> "$text (${refinement.id})" }
    var onCheckReady: suspend () -> Unit = {}

    override suspend fun polish(
        text: String,
        channel: Channel,
        options: PolishOptions,
    ): PolishResult {
        calls += Call(text, channel)
        requestedOptions += options
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

/** In-memory [AppSettings]; [modes] starts with every mode's defaults. */
class FakeAppSettings(
    var provider: Provider = Provider.ANTHROPIC,
) : AppSettings {
    override val modes = MutableStateFlow(ModeSettings())
    override val palette = MutableStateFlow(PalettePreset.WRITING_DESK)

    /** The current mode's last channel, as stored. */
    val channel: Channel get() = modes.value.profile.lastChannel

    private fun update(
        mode: Mode,
        change: (ModeProfile) -> ModeProfile,
    ) {
        val current = modes.value
        modes.value =
            when (mode) {
                Mode.WORK -> current.copy(work = change(current.work))
                Mode.PERSONAL -> current.copy(personal = change(current.personal))
            }
    }

    override suspend fun setMode(mode: Mode) {
        modes.value = modes.value.copy(current = mode)
    }

    override suspend fun setLastChannel(
        mode: Mode,
        channel: Channel,
    ) = update(mode) { it.copy(lastChannel = channel) }

    override suspend fun setChannelVisible(
        mode: Mode,
        channel: Channel,
        visible: Boolean,
    ): Boolean {
        val updated = modes.value[mode].withVisible(channel, visible) ?: return false
        update(mode) { updated }
        return true
    }

    override suspend fun setOutputLanguage(
        mode: Mode,
        language: OutputLanguage,
    ) = update(mode) { it.copy(outputLanguage = language) }

    override suspend fun setLearningSummary(
        mode: Mode,
        enabled: Boolean,
    ) = update(mode) { it.copy(learningSummary = enabled) }

    override suspend fun setPalette(palette: PalettePreset) {
        this.palette.value = palette
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

/**
 * A history kept in memory, starting with [saved]; every save goes to [save] (which may throw to
 * simulate a disk failure). File work runs in place, so `advanceUntilIdle` covers it.
 */
fun testHistory(
    saved: List<HistoryEntry> = emptyList(),
    limit: Int = HistoryStore.DEFAULT_LIMIT,
    save: (List<HistoryEntry>) -> Unit = {},
): HistoryRepository =
    HistoryRepository(
        loadEntries = { saved },
        saveEntries = save,
        limit = limit,
        ioDispatcher = Dispatchers.Unconfined,
    )
