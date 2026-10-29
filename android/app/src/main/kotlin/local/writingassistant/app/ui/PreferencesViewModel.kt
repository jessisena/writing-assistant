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
import local.writingassistant.app.data.PalettePreset
import local.writingassistant.core.Channel

/** The preferences below the provider settings, as last stored. */
data class PreferencesState(
    val disabledChannels: Set<Channel>,
    val learningSummaryEnabled: Boolean,
    val palette: PalettePreset,
) {
    /** Whether [channel] is the only one left on, so turning it off is not allowed. */
    fun isLastEnabled(channel: Channel): Boolean =
        channel !in disabledChannels && Channel.entries.count { it !in disabledChannels } == 1
}

/** Reads and changes the channel, learning summary and palette preferences. */
class PreferencesViewModel(
    private val settings: AppSettings,
) : ViewModel() {
    /** Null until every preference has loaded. */
    val state: StateFlow<PreferencesState?> =
        combine(
            settings.disabledChannels,
            settings.learningSummaryEnabled,
            settings.palette,
            ::PreferencesState,
        ).stateIn(viewModelScope, SharingStarted.WhileSubscribed(STOP_TIMEOUT_MS), null)

    private val mutableFailure = MutableStateFlow<String?>(null)

    /** The class of the exception that kept the last change from being saved, if any. */
    val failure: StateFlow<String?> = mutableFailure.asStateFlow()

    /** Ignored when it would turn off the last enabled channel. */
    fun setChannelEnabled(
        channel: Channel,
        enabled: Boolean,
    ) {
        if (!enabled && state.value?.isLastEnabled(channel) != false) return
        save { settings.setChannelEnabled(channel, enabled) }
    }

    fun setLearningSummaryEnabled(enabled: Boolean) =
        save {
            settings.setLearningSummaryEnabled(enabled)
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
