package local.writingassistant.app.ui

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.app.data.AppSettings
import local.writingassistant.app.data.HistoryRepository
import local.writingassistant.core.Channel
import local.writingassistant.core.HistoryEntry
import local.writingassistant.core.HistoryStoreException
import local.writingassistant.core.PolishError
import local.writingassistant.core.PolishResult
import local.writingassistant.core.Polishing
import local.writingassistant.core.Refinement
import java.util.UUID

/**
 * The composer's state and requests, shared by every screen that shows the composer. It lives
 * as long as [scope] (the app), so closing the bottom sheet mid-request keeps the result for
 * the next screen that opens. One request runs at a time; [ComposerEvent.Cancel] stops it,
 * and a generation number makes sure a cancelled or replaced request can't overwrite newer
 * state.
 *
 * Follows the enabled channels and the learning-summary switch in [settings]. Each successful
 * polish is recorded in [history] and becomes the current entry, whose output is kept up to
 * date by refinements, [ComposerEvent.SaveOutput], and before the screen moves on to other
 * text. History failures go to the error banner and never hide a result.
 */
class ComposerSession(
    private val polisher: Polishing,
    private val settings: AppSettings,
    private val apiKeyStore: ApiKeyStore,
    private val history: HistoryRepository,
    private val scope: CoroutineScope,
) {
    private val mutableState = MutableStateFlow(ComposerState())
    val state: StateFlow<ComposerState> = mutableState.asStateFlow()

    private var job: Job? = null
    private var generation = 0
    private var lastFailed: ComposerEvent? = null
    private var channelChosen = false

    /** The history entry the output on screen belongs to; null when it belongs to none. */
    private var currentHistoryId: String? = null

    init {
        launchReporting { history.load() }
        launchReporting {
            val restored = settings.lastChannel()
            if (restored != null && !channelChosen) {
                mutableState.update { it.copy(channel = restored).withEnabledChannel() }
            }
        }
        launchReporting { settings.disabledChannels.collect(::applyDisabledChannels) }
        launchReporting {
            settings.learningSummaryEnabled.collect { enabled ->
                mutableState.update { it.copy(showLearningSummary = enabled) }
            }
        }
    }

    fun onEvent(event: ComposerEvent) {
        when (event) {
            is ComposerEvent.Open -> open(event.text)
            is ComposerEvent.InputChanged -> mutableState.update { it.copy(input = event.text) }
            is ComposerEvent.OutputChanged -> mutableState.update { it.copy(output = event.text) }
            is ComposerEvent.ChannelSelected -> selectChannel(event.channel)
            ComposerEvent.Polish -> polish()
            is ComposerEvent.Refine -> refine(event.refinement)
            ComposerEvent.Cancel -> cancel()
            ComposerEvent.DismissError -> mutableState.update { it.copy(error = null) }
            ComposerEvent.Retry -> lastFailed?.let(::onEvent)
            ComposerEvent.RefreshApiKey -> refreshApiKey()
            ComposerEvent.SaveOutput -> saveOutput()
            is ComposerEvent.RestoreHistory -> restore(event.id)
        }
    }

    private fun open(text: String) {
        if (text == state.value.input) return
        cancel()
        saveOutput()
        currentHistoryId = null
        lastFailed = null
        mutableState.update {
            ComposerState(
                input = text,
                channel = it.channel,
                needsApiKey = it.needsApiKey,
                enabledChannels = it.enabledChannels,
                showLearningSummary = it.showLearningSummary,
            )
        }
    }

    /** Shows every channel not in [disabled] (all of them if that leaves none). */
    private fun applyDisabledChannels(disabled: Set<Channel>) {
        val enabled = Channel.entries.filterNot { it in disabled }.ifEmpty { Channel.entries }
        mutableState.update { it.copy(enabledChannels = enabled).withEnabledChannel() }
    }

    /** Selects the first enabled channel when the selected one is hidden; not persisted. */
    private fun ComposerState.withEnabledChannel(): ComposerState =
        if (channel in enabledChannels) this else copy(channel = enabledChannels.first())

    /** Writes the output on screen into the current history entry, if it changed. */
    private fun saveOutput() {
        val id = currentHistoryId ?: return
        val output = state.value.output
        launchReporting { history.updateOutput(id, output) }
    }

    private fun restore(id: String) {
        if (state.value.isWorking) return
        saveOutput()
        val entry = history.entries.value.firstOrNull { it.id == id } ?: return
        currentHistoryId = entry.id
        channelChosen = true
        lastFailed = null
        mutableState.update {
            it
                .copy(
                    input = entry.input,
                    output = entry.output,
                    channel = entry.channel,
                    result = entry.toResult(),
                    error = null,
                )
        }
    }

    private fun refreshApiKey() {
        launchReporting {
            val missing = apiKeyStore.read(settings.provider()).isNullOrBlank()
            mutableState.update { it.copy(needsApiKey = missing) }
        }
    }

    private fun selectChannel(channel: Channel) {
        channelChosen = true
        mutableState.update { it.copy(channel = channel) }
        launchReporting { settings.setLastChannel(channel) }
    }

    /** Runs [body] in [scope], showing any failure in the error banner instead of crashing. */
    private fun launchReporting(body: suspend () -> Unit) {
        scope.launch {
            try {
                body()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = asPolishError(e)
                mutableState.update { it.copy(error = error) }
            }
        }
    }

    private fun polish() {
        val current = state.value
        if (!current.canPolish) return
        saveOutput()
        start(ComposerEvent.Polish, null) {
            val result =
                polisher.polish(current.input, current.channel, current.showLearningSummary)
            val (entryId, historyError) = record(result, current.input, current.channel)
            return@start { state: ComposerState ->
                currentHistoryId = entryId
                state.copy(result = result, output = result.polishedText, error = historyError)
            }
        }
    }

    /**
     * Records [result] and returns the new entry's id with the failure to save it, if any.
     * A failed save still adds the entry to the history in memory.
     */
    private suspend fun record(
        result: PolishResult,
        input: String,
        channel: Channel,
    ): Pair<String, PolishError?> {
        val id = UUID.randomUUID().toString()
        val error = historyFailure { history.record(result, input, channel, id) }
        return id to error
    }

    /** Runs [body] and returns its failure as a [PolishError] instead of throwing it. */
    private suspend fun historyFailure(body: suspend () -> Unit): PolishError? =
        try {
            body()
            null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            asPolishError(e)
        }

    private fun refine(refinement: Refinement) {
        val current = state.value
        if (!current.canUseOutput) return
        val entryId = currentHistoryId
        start(ComposerEvent.Refine(refinement), refinement) {
            val refined = polisher.refine(current.output, current.channel, refinement)
            val historyError = entryId?.let { historyFailure { history.updateOutput(it, refined) } }
            return@start { state: ComposerState ->
                state.copy(output = refined, error = historyError)
            }
        }
    }

    private fun start(
        request: ComposerEvent,
        refinement: Refinement?,
        work: suspend () -> (ComposerState) -> ComposerState,
    ) {
        val requestGeneration = ++generation
        mutableState.update {
            it.copy(
                phase = ComposerState.Phase.Working(refinement),
                error = null,
            )
        }
        job =
            scope.launch {
                var failure: PolishError? = null
                val apply =
                    try {
                        work()
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        val error = asPolishError(e)
                        failure = error
                        failed(error)
                    }
                if (requestGeneration != generation) return@launch
                job = null
                lastFailed = request.takeIf { failure != null }
                mutableState.update { apply(it.copy(phase = ComposerState.Phase.Idle)) }
            }
    }

    private fun asPolishError(e: Exception): PolishError =
        when (e) {
            is PolishError -> e
            is HistoryStoreException -> PolishError.HistoryFailed(e.message.orEmpty())
            else -> PolishError.Unexpected(e.javaClass.simpleName)
        }

    private fun failed(error: PolishError): (ComposerState) -> ComposerState =
        { state ->
            val missingKey = error == PolishError.MissingApiKey
            state.copy(error = error, needsApiKey = state.needsApiKey || missingKey)
        }

    private fun cancel() {
        val running = job?.takeIf { it.isActive } ?: return
        generation++
        job = null
        running.cancel()
        mutableState.update { it.copy(phase = ComposerState.Phase.Idle) }
    }
}

private fun HistoryEntry.toResult() =
    PolishResult(
        polishedText = output,
        learningSummary = learningSummary,
        detectedLanguage = detectedLanguage,
        wasTranslated = wasTranslated,
        modelUsed = modelUsed,
    )
