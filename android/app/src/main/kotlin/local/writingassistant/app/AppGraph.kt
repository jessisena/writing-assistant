package local.writingassistant.app

import android.content.Context
import local.writingassistant.app.data.ApiKeyStore
import local.writingassistant.app.data.AppSettings
import local.writingassistant.core.Polishing

/** App-wide singletons, built once by [WritingAssistantApp]. */
interface AppGraph {
    val polisher: Polishing
    val apiKeyStore: ApiKeyStore
    val settings: AppSettings
}

/** Wires the real implementations. Owned by the main session's integration step. */
class DefaultAppGraph(
    private val context: Context,
) : AppGraph {
    override val polisher: Polishing by lazy { TODO("integration ($context)") }
    override val apiKeyStore: ApiKeyStore by lazy { TODO("integration") }
    override val settings: AppSettings by lazy { TODO("integration") }
}
