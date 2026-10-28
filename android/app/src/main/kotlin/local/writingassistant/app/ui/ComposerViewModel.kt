package local.writingassistant.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import local.writingassistant.app.AppGraph
import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.app.data.AppSettings
import local.writingassistant.core.Channel
import local.writingassistant.core.PolishError
import local.writingassistant.core.PolishResult
import local.writingassistant.core.Polishing
import local.writingassistant.core.Refinement

/** Everything the composer screen and the bottom sheet render. */
data class ComposerState(
    val input: String = "",
    val channel: Channel = Channel.SLACK,
    val phase: Phase = Phase.Idle,
    val result: PolishResult? = null,
    /** The polished text as shown and edited by the user; starts as `result.polishedText`. */
    val output: String = "",
    val error: PolishError? = null,
    /** True once the key store was read and holds no API key; Polish is disabled meanwhile. */
    val needsApiKey: Boolean = false,
) {
    val isWorking: Boolean get() = phase is Phase.Working

    /** Whether the Polish action is available. */
    val canPolish: Boolean get() = !isWorking && !needsApiKey && input.isNotBlank()

    /** Whether Copy, Replace and the refinements are available. */
    val canUseOutput: Boolean get() = !isWorking && output.isNotBlank()

    sealed interface Phase {
        data object Idle : Phase

        /** A polish (refinement == null) or refinement request is in flight. */
        data class Working(
            val refinement: Refinement?,
        ) : Phase
    }
}

sealed interface ComposerEvent {
    data class InputChanged(
        val text: String,
    ) : ComposerEvent

    data class OutputChanged(
        val text: String,
    ) : ComposerEvent

    data class ChannelSelected(
        val channel: Channel,
    ) : ComposerEvent

    data object Polish : ComposerEvent

    data class Refine(
        val refinement: Refinement,
    ) : ComposerEvent

    data object Cancel : ComposerEvent

    data object DismissError : ComposerEvent

    /** Runs the request that last failed again. */
    data object Retry : ComposerEvent

    /** Reads the key store again, e.g. after returning from Settings. */
    data object RefreshApiKey : ComposerEvent
}

/**
 * Drives the composer. One request runs at a time; [ComposerEvent.Cancel] stops it, and a
 * generation number makes sure a cancelled or replaced request can't overwrite newer state.
 */
class ComposerViewModel(
    private val polisher: Polishing,
    private val settings: AppSettings,
    private val apiKeyStore: ApiKeyStore,
) : ViewModel() {
    private val mutableState = MutableStateFlow(ComposerState())
    val state: StateFlow<ComposerState> = mutableState.asStateFlow()

    private var job: Job? = null
    private var generation = 0
    private var lastFailed: ComposerEvent? = null
    private var channelChosen = false

    init {
        viewModelScope.launch {
            val restored = settings.lastChannel()
            if (restored != null &&
                !channelChosen
            ) {
                mutableState.update { it.copy(channel = restored) }
            }
        }
        refreshApiKey()
    }

    fun onEvent(event: ComposerEvent) {
        when (event) {
            is ComposerEvent.InputChanged -> mutableState.update { it.copy(input = event.text) }
            is ComposerEvent.OutputChanged -> mutableState.update { it.copy(output = event.text) }
            is ComposerEvent.ChannelSelected -> selectChannel(event.channel)
            ComposerEvent.Polish -> polish()
            is ComposerEvent.Refine -> refine(event.refinement)
            ComposerEvent.Cancel -> cancel()
            ComposerEvent.DismissError -> mutableState.update { it.copy(error = null) }
            ComposerEvent.Retry -> lastFailed?.let(::onEvent)
            ComposerEvent.RefreshApiKey -> refreshApiKey()
        }
    }

    private fun refreshApiKey() {
        viewModelScope.launch {
            val missing = apiKeyStore.read().isNullOrBlank()
            mutableState.update { it.copy(needsApiKey = missing) }
        }
    }

    private fun selectChannel(channel: Channel) {
        channelChosen = true
        mutableState.update { it.copy(channel = channel) }
        viewModelScope.launch { settings.setLastChannel(channel) }
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
            viewModelScope.launch {
                var failure: PolishError? = null
                val apply =
                    try {
                        work()
                    } catch (error: PolishError) {
                        failure = error
                        failed(error)
                    }
                if (requestGeneration != generation) return@launch
                job = null
                lastFailed = request.takeIf { failure != null }
                mutableState.update { apply(it.copy(phase = ComposerState.Phase.Idle)) }
            }
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

    companion object {
        /** Builds the view model from the app's singletons, for `viewModel(factory = …)`. */
        fun factory(graph: AppGraph): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { ComposerViewModel(graph.polisher, graph.settings, graph.apiKeyStore) }
            }
    }
}
