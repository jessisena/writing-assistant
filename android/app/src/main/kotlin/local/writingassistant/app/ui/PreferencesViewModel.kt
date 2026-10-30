package local.writingassistant.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import local.writingassistant.app.AppGraph
import local.writingassistant.app.data.AppSettings
import local.writingassistant.app.data.ModeProfile
import local.writingassistant.app.data.ModeSettings
import local.writingassistant.app.data.PalettePreset
import local.writingassistant.core.Channel
import local.writingassistant.core.Mode
import local.writingassistant.core.OutputLanguage

/**
 * The preferences below the provider settings, as last stored.
 *
 * @property editing The mode whose settings are shown; starts as the current mode.
 */
data class PreferencesState(
    val modes: ModeSettings,
    val palette: PalettePreset,
    val editing: Mode,
) {
    /** The settings of the mode being edited. */
    val profile: ModeProfile get() = modes[editing]
}

/** Reads and changes each mode's channels, language and learning summary, and the palette. */
class PreferencesViewModel(
    private val settings: AppSettings,
) : ViewModel() {
    private val editing = MutableStateFlow<Mode?>(null)

    /** Null until every preference has loaded. */
    val state: StateFlow<PreferencesState?> =
        combine(settings.modes, settings.palette, editing) { modes, palette, editing ->
            PreferencesState(modes, palette, editing ?: modes.current)
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_TIMEOUT_MS), null)

    private val mutableFailure = MutableStateFlow<String?>(null)

    /** The class of the exception that kept the last change from being saved, if any. */
    val failure: StateFlow<String?> = mutableFailure.asStateFlow()

    /** Shows [mode]'s settings; changes nothing stored. */
    fun edit(mode: Mode) {
        editing.value = mode
    }

    /** Shows or hides [channel] in the mode being edited; the only visible channel stays. */
    fun setChannelVisible(
        channel: Channel,
        visible: Boolean,
    ) {
        val mode = state.value?.editing ?: return
        save { settings.setChannelVisible(mode, channel, visible) }
    }

    fun setOutputLanguage(language: OutputLanguage) {
        val mode = state.value?.editing ?: return
        save { settings.setOutputLanguage(mode, language) }
    }

    fun setLearningSummary(enabled: Boolean) {
        val mode = state.value?.editing ?: return
        save { settings.setLearningSummary(mode, enabled) }
    }

    fun setPalette(palette: PalettePreset) = save { settings.setPalette(palette) }

    private fun save(change: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                change()
                mutableFailure.value = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                mutableFailure.value = e.javaClass.simpleName
            }
        }
    }

    companion object {
        private const val STOP_TIMEOUT_MS = 5_000L

        /** Builds the view model from the app's singletons, for `viewModel(factory = …)`. */
        fun factory(graph: AppGraph): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { PreferencesViewModel(graph.settings) }
            }
    }
}
