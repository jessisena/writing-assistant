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
import local.writingassistant.app.data.AppSettings
import local.writingassistant.core.PolishError
import local.writingassistant.core.Polishing
import local.writingassistant.core.Provider
import local.writingassistant.core.api.isWellFormedKey

/** What the Settings screen renders. */
data class SettingsState(
    /** The provider whose key is being edited; requests go to it too. */
    val provider: Provider = Provider.ANTHROPIC,
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
 * Picks the provider and edits its stored API key. Choosing a provider saves it right away, so
 * the next request goes to it. When a provider has no stored key, the field starts with its
 * [debugApiKeys] entry (the debug build's `local.properties` key), which is only stored once the
 * user saves it.
 */
class SettingsViewModel(
    private val apiKeyStore: ApiKeyStore,
    private val settings: AppSettings,
    private val polisher: Polishing,
    private val debugApiKeys: Map<Provider, String>,
) : ViewModel() {
    private val mutableState = MutableStateFlow(SettingsState())
    val state: StateFlow<SettingsState> = mutableState.asStateFlow()
    private var providerChosen = false

    init {
        launchReporting {
            val provider = settings.provider()
            if (providerChosen) return@launchReporting
            mutableState.update { it.copy(provider = provider) }
            loadKey(provider)
        }
    }

    /** Makes [provider] the one requests go to and shows its key. */
    fun selectProvider(provider: Provider) {
        if (provider == state.value.provider) return
        providerChosen = true
        mutableState.update {
            SettingsState(provider = provider, status = SettingsState.Status.Idle)
        }
        launchReporting {
            settings.setProvider(provider)
            loadKey(provider)
        }
    }

    fun onKeyChange(key: String) {
        mutableState.update { it.copy(key = key, status = SettingsState.Status.Idle) }
    }

    fun save() {
        launchReporting { store() }
    }

    /** Saves the key, then makes a cheap call to check that the selected provider accepts it. */
    fun test() {
        launchReporting {
            val provider = store() ?: return@launchReporting
            updateFor(provider) { it.copy(status = SettingsState.Status.Testing) }
            // Already saved on selection; saved again so the check can't reach another provider.
            settings.setProvider(provider)
            polisher.checkReady()
            updateFor(provider) { it.copy(status = SettingsState.Status.TestPassed) }
        }
    }

    fun clear() {
        launchReporting {
            val provider = state.value.provider
            apiKeyStore.clear(provider)
            updateFor(provider) {
                SettingsState(provider = provider, status = SettingsState.Status.Cleared)
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

    /** Applies [change] unless another provider was chosen while the work ran. */
    private fun updateFor(
        provider: Provider,
        change: (SettingsState) -> SettingsState,
    ) {
        mutableState.update { if (it.provider == provider) change(it) else it }
    }

    /** Shows [provider]'s stored key, or its debug prefill when none is stored. */
    private suspend fun loadKey(provider: Provider) {
        val stored = apiKeyStore.read(provider)
        val key = stored ?: debugApiKeys[provider]?.takeIf { it.isNotBlank() }.orEmpty()
        updateFor(provider) { it.copy(key = key, hasStoredKey = stored != null) }
    }

    /**
     * Stores the typed key for the selected provider.
     *
     * @return The provider the key was stored for, or null when the field is blank.
     * @throws PolishError.MalformedApiKey when the key can't be sent as an HTTP header.
     */
    private suspend fun store(): Provider? {
        val provider = state.value.provider
        val key = state.value.key.trim()
        if (key.isEmpty()) return null
        if (!isWellFormedKey(key)) throw PolishError.MalformedApiKey
        apiKeyStore.write(provider, key)
        updateFor(provider) {
            it.copy(key = key, hasStoredKey = true, status = SettingsState.Status.Saved)
        }
        return provider
    }

    companion object {
        /** Builds the view model from the app's singletons, for `viewModel(factory = …)`. */
        fun factory(graph: AppGraph): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    SettingsViewModel(
                        graph.apiKeyStore,
                        graph.settings,
                        graph.polisher,
                        mapOf(
                            Provider.ANTHROPIC to BuildConfig.DEBUG_API_KEY,
                            Provider.GROQ to BuildConfig.DEBUG_GROQ_API_KEY,
                        ),
                    )
                }
            }
    }
}
