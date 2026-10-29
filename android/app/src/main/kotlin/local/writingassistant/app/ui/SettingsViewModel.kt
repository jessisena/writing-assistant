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

    /** The provider whose field was typed in since its key started loading, if any. */
    private var keyEditedFor: Provider? = null

    init {
        launchReporting(state.value.provider) {
            val provider = settings.provider()
            if (providerChosen) return@launchReporting
            mutableState.update { it.copy(provider = provider) }
            launchReporting(provider) { loadKey(provider) }
        }
    }

    /**
     * Makes [provider] the one requests go to and shows its key. An explicit choice wins over the
     * saved provider still loading; ignored while a test runs so the test can't change providers.
     */
    fun selectProvider(provider: Provider) {
        val current = state.value
        if (current.isTesting || (providerChosen && provider == current.provider)) return
        providerChosen = true
        keyEditedFor = null
        mutableState.update {
            SettingsState(provider = provider, status = SettingsState.Status.Idle)
        }
        launchReporting(provider) {
            settings.setProvider(provider)
            loadKey(provider)
        }
    }

    fun onKeyChange(key: String) {
        keyEditedFor = state.value.provider
        mutableState.update {
            val status = if (it.isTesting) it.status else SettingsState.Status.Idle
            it.copy(key = key, status = status)
        }
    }

    fun save() {
        val provider = state.value.provider
        val key = state.value.key
        launchReporting(provider) {
            if (store(provider, key)) {
                updateFor(provider) { it.copy(status = SettingsState.Status.Saved) }
            }
        }
    }

    /**
     * Saves the key, then makes a cheap call to check that the selected provider accepts it. The
     * status turns to Testing before anything suspends, so the provider can't change mid-test.
     */
    fun test() {
        val before = state.value
        if (before.isTesting) return
        val provider = before.provider
        mutableState.update { it.copy(status = SettingsState.Status.Testing) }
        launchReporting(provider) {
            if (!store(provider, before.key)) {
                updateFor(provider) { it.copy(status = before.status) }
                return@launchReporting
            }
            polisher.checkReady()
            updateFor(provider) { it.copy(status = SettingsState.Status.TestPassed) }
        }
    }

    fun clear() {
        val provider = state.value.provider
        launchReporting(provider) {
            apiKeyStore.clear(provider)
            updateFor(provider) {
                SettingsState(provider = provider, status = SettingsState.Status.Cleared)
            }
        }
    }

    /**
     * Runs [body], showing any failure as [SettingsState.Status.Failed] unless another provider
     * than [provider] was chosen while it ran.
     */
    private fun launchReporting(
        provider: Provider,
        body: suspend () -> Unit,
    ) {
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
            updateFor(provider) { it.copy(status = SettingsState.Status.Failed(error.message)) }
        }
    }

    /** Applies [change] unless another provider was chosen while the work ran. */
    private fun updateFor(
        provider: Provider,
        change: (SettingsState) -> SettingsState,
    ) {
        mutableState.update { if (it.provider == provider) change(it) else it }
    }

    /**
     * Shows [provider]'s stored key, or its debug prefill when none is stored. Keeps what the user
     * typed in the field while the key loaded.
     */
    private suspend fun loadKey(provider: Provider) {
        val stored = apiKeyStore.read(provider)
        val key = stored ?: debugApiKeys[provider]?.takeIf { it.isNotBlank() }.orEmpty()
        updateFor(provider) {
            val shown = if (keyEditedFor == provider) it.key else key
            it.copy(key = shown, hasStoredKey = stored != null)
        }
    }

    /**
     * Stores [typed], trimmed, as [provider]'s key.
     *
     * @return False when the key is blank, so nothing was stored.
     * @throws PolishError.MalformedApiKey when the key can't be sent as an HTTP header.
     */
    private suspend fun store(
        provider: Provider,
        typed: String,
    ): Boolean {
        val key = typed.trim()
        if (key.isEmpty()) return false
        if (!isWellFormedKey(key)) throw PolishError.MalformedApiKey
        apiKeyStore.write(provider, key)
        updateFor(provider) { it.copy(key = key, hasStoredKey = true) }
        return true
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
