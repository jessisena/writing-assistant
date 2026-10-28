package local.writingassistant.app.ui

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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
) {
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
}

class ComposerViewModel(
    private val polisher: Polishing,
    private val settings: AppSettings,
) : ViewModel() {
    private val mutableState = MutableStateFlow(ComposerState())
    val state: StateFlow<ComposerState> = mutableState.asStateFlow()

    fun onEvent(event: ComposerEvent): Unit = TODO("ui worker ($polisher, $settings, $event)")
}
