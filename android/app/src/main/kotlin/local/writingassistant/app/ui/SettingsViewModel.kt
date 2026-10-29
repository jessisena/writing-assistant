package local.writingassistant.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import local.writingassistant.app.AppGraph
import local.writingassistant.app.BuildConfig
import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.core.PolishError
import local.writingassistant.core.Polishing
import local.writingassistant.core.Provider
import local.writingassistant.core.api.isWellFormedKey

/** What the Settings screen renders. */
data class SettingsState(
    /** The key as typed; never logged. */
    val key: String = "",
    val hasStoredKey: Boolean = false,
    val status: Status = Status.Idle,
) {
    val isTesting: Boolean get() = status == Status.Testing

    sealed interface Status {
        data object Idle : Status

        data object Saved : Status

        data object Cleared : Status

        data object Testing : Status

        data object TestPassed : Status

        /** Loading, saving, testing or clearing the key failed; [message] is shown as is. */
        data class Failed(
            val message: String,
        ) : Status
    }
}

/**
 * Edits the stored API key. When nothing is stored yet, the field starts with [debugApiKey]
 * (the debug build's `local.properties` key), which is only stored once the user saves it.
 */
class SettingsViewModel(
    private val apiKeyStore: ApiKeyStore,
    private val polisher: Polishing,
    debugApiKey: String,
) : ViewModel() {
    private val mutableState = MutableStateFlow(SettingsState())
    val state: StateFlow<SettingsState> = mutableState.asStateFlow()

    init {
        launchReporting {
            val stored = apiKeyStore.read(Provider.ANTHROPIC)
            val key = stored ?: debugApiKey.takeIf { it.isNotBlank() }.orEmpty()
            mutableState.update { it.copy(key = key, hasStoredKey = stored != null) }
        }
    }

    fun onKeyChange(key: String) {
        mutableState.update { it.copy(key = key, status = SettingsState.Status.Idle) }
    }

    fun save() {
        launchReporting { store() }
    }

    /** Saves the key, then makes a cheap call to check that Claude accepts it. */
    fun test() {
        launchReporting {
            if (!store()) return@launchReporting
            mutableState.update { it.copy(status = SettingsState.Status.Testing) }
            polisher.checkReady()
            mutableState.update { it.copy(status = SettingsState.Status.TestPassed) }
        }
    }

    fun clear() {
        launchReporting {
            apiKeyStore.clear(Provider.ANTHROPIC)
            mutableState.update {
                SettingsState(key = "", hasStoredKey = false, status = SettingsState.Status.Cleared)
            }
        }
    }

    /** Runs [body], showing any failure as [SettingsState.Status.Failed]. */
    private fun launchReporting(body: suspend () -> Unit) {
        viewModelScope.launch {
            val error =
                try {
                    body()
                    return@launch
                } catch (e: CancellationException) {
                    throw e
                } catch (e: PolishError) {
                    e
                } catch (e: Exception) {
                    PolishError.Unexpected(e.javaClass.simpleName)
                }
            mutableState.update { it.copy(status = SettingsState.Status.Failed(error.message)) }
        }
    }

    /** @throws PolishError.MalformedApiKey when the key can't be sent as an HTTP header. */
    private suspend fun store(): Boolean {
        val key = state.value.key.trim()
        if (key.isEmpty()) return false
        if (!isWellFormedKey(key)) throw PolishError.MalformedApiKey
        apiKeyStore.write(Provider.ANTHROPIC, key)
        mutableState.update {
            it.copy(key = key, hasStoredKey = true, status = SettingsState.Status.Saved)
        }
        return true
    }

    companion object {
        /** Builds the view model from the app's singletons, for `viewModel(factory = …)`. */
        fun factory(graph: AppGraph): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    SettingsViewModel(graph.apiKeyStore, graph.polisher, BuildConfig.DEBUG_API_KEY)
                }
            }
    }
}
