package local.writingassistant.app

import android.content.Context
import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.app.data.AppSettings
import local.writingassistant.app.data.AssetPromptReader
import local.writingassistant.app.data.DataStoreAppSettings
import local.writingassistant.app.data.KeystoreApiKeyStore
import local.writingassistant.core.PolishService
import local.writingassistant.core.Polishing
import local.writingassistant.core.api.AnthropicClient

/** App-wide singletons, built once by [WritingAssistantApp]. */
interface AppGraph {
    val polisher: Polishing
    val apiKeyStore: ApiKeyStore
    val settings: AppSettings
}

/** Wires the real implementations. */
class DefaultAppGraph(
    context: Context,
) : AppGraph {
    private val appContext = context.applicationContext

    override val apiKeyStore: ApiKeyStore by lazy { KeystoreApiKeyStore(appContext) }
    override val settings: AppSettings by lazy { DataStoreAppSettings(appContext) }
    override val polisher: Polishing by lazy {
        PolishService(
            client = AnthropicClient(apiKey = { apiKeyStore.read() }),
            prompts = AssetPromptReader(appContext.assets),
        )
    }
}
