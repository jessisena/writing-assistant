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
import local.writingassistant.core.PolishError
import local.writingassistant.core.Polishing
import local.writingassistant.core.Refinement

/**
 * The composer's state and requests, shared by every screen that shows the composer. It lives
 * as long as [scope] (the app), so closing the bottom sheet mid-request keeps the result for
 * the next screen that opens. One request runs at a time; [ComposerEvent.Cancel] stops it,
 * and a generation number makes sure a cancelled or replaced request can't overwrite newer
 * state.
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

    init {
        launchReporting {
            val restored = settings.lastChannel()
            if (restored != null && !channelChosen) {
                mutableState.update { it.copy(channel = restored) }
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
            ComposerEvent.SaveOutput -> TODO()
            is ComposerEvent.RestoreHistory -> TODO()
        }
    }

    private fun open(text: String) {
        if (text == state.value.input) return
        cancel()
        lastFailed = null
        mutableState.update {
            ComposerState(input = text, channel = it.channel, needsApiKey = it.needsApiKey)
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
        start(ComposerEvent.Polish, null) {
            val result = polisher.polish(current.input, current.channel)
            return@start { state: ComposerState ->
                state.copy(result = result, output = result.polishedText)
            }
        }
    }

    private fun refine(refinement: Refinement) {
        val current = state.value
        if (!current.canUseOutput) return
        start(ComposerEvent.Refine(refinement), refinement) {
            val refined = polisher.refine(current.output, current.channel, refinement)
            return@start { state: ComposerState -> state.copy(output = refined) }
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
        e as? PolishError ?: PolishError.Unexpected(e.javaClass.simpleName)

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
