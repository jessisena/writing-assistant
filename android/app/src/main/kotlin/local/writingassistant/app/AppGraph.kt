package local.writingassistant.app

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.app.data.AppSettings
import local.writingassistant.app.data.AssetPromptReader
import local.writingassistant.app.data.DataStoreAppSettings
import local.writingassistant.app.data.KeystoreApiKeyStore
import local.writingassistant.app.ui.ComposerSession
import local.writingassistant.core.Backend
import local.writingassistant.core.LlmClient
import local.writingassistant.core.PolishService
import local.writingassistant.core.Polishing
import local.writingassistant.core.Provider
import local.writingassistant.core.api.AnthropicClient
import local.writingassistant.core.api.GroqClient

/** App-wide singletons, built once by [WritingAssistantApp]. */
interface AppGraph {
    val polisher: Polishing
    val apiKeyStore: ApiKeyStore
    val settings: AppSettings

    /** The composer shared by the app and the bottom sheets; outlives any one screen. */
    val composerSession: ComposerSession
}

/** Wires the real implementations. */
class DefaultAppGraph(
    context: Context,
) : AppGraph {
    private val appContext = context.applicationContext

    override val apiKeyStore: ApiKeyStore by lazy { KeystoreApiKeyStore(appContext) }
    override val settings: AppSettings by lazy { DataStoreAppSettings(appContext) }
    private val anthropic by lazy {
        AnthropicClient(apiKey = { apiKeyStore.read(Provider.ANTHROPIC) })
    }
    private val groq by lazy { GroqClient(apiKey = { apiKeyStore.read(Provider.GROQ) }) }

    /** Uses whichever provider Settings currently selects, read again for every request. */
    override val polisher: Polishing by lazy {
        PolishService(
            backend = {
                val provider = settings.provider()
                Backend(clientFor(provider), provider.models)
            },
            prompts = AssetPromptReader(appContext.assets),
        )
    }
    override val composerSession: ComposerSession by lazy {
        ComposerSession(
            polisher,
            settings,
            apiKeyStore,
            CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        )
    }

    private fun clientFor(provider: Provider): LlmClient =
        when (provider) {
            Provider.ANTHROPIC -> anthropic
            Provider.GROQ -> groq
        }
}
