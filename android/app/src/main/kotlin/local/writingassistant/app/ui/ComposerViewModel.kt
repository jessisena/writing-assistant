package local.writingassistant.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.flow.StateFlow
import local.writingassistant.app.AppGraph
import local.writingassistant.core.Channel
import local.writingassistant.core.PolishError
import local.writingassistant.core.PolishResult
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
    /** The channels offered as chips, in [Channel] order; never empty. */
    val enabledChannels: List<Channel> = Channel.entries,
    /** False when the user turned the learning summary off in Settings. */
    val showLearningSummary: Boolean = true,
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
    /**
     * Loads [text] handed over by another app. The same text as the current input keeps the
     * session as it is, so reopening the sheet picks up a result that finished meanwhile;
     * other text cancels any request and starts over.
     */
    data class Open(
        val text: String,
    ) : ComposerEvent

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

    /** Writes the output on screen into its history entry; sent before Copy and Replace. */
    data object SaveOutput : ComposerEvent

    /** Loads history entry [id] (input, output, channel and result); ignored while working. */
    data class RestoreHistory(
        val id: String,
    ) : ComposerEvent
}

/**
 * Connects a screen to the app-wide [ComposerSession] and checks for an API key when the
 * screen opens. Clearing the view model (closing the sheet or the app) leaves running
 * requests and their results in the session.
 */
class ComposerViewModel(
    private val session: ComposerSession,
) : ViewModel() {
    val state: StateFlow<ComposerState> = session.state

    init {
        session.onEvent(ComposerEvent.RefreshApiKey)
    }

    fun onEvent(event: ComposerEvent) = session.onEvent(event)

    companion object {
        /** Builds the view model from the app's singletons, for `viewModel(factory = …)`. */
        fun factory(graph: AppGraph): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { ComposerViewModel(graph.composerSession) }
            }
    }
}
