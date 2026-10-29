package local.writingassistant.app.intents

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import local.writingassistant.app.AppGraph
import local.writingassistant.app.WritingAssistantApp
import local.writingassistant.app.ui.ComposerSession
import local.writingassistant.app.ui.FakeApiKeyStore
import local.writingassistant.app.ui.FakeAppSettings
import local.writingassistant.app.ui.FakePolishing
import local.writingassistant.app.ui.testHistory
import local.writingassistant.core.PromptOverrideStore
import java.nio.file.Files

class FakeAppGraph : AppGraph {
    override val polisher = FakePolishing()
    override val apiKeyStore = FakeApiKeyStore()
    override val settings = FakeAppSettings()
    override val promptStore =
        PromptOverrideStore(Files.createTempDirectory("prompts").toFile()) { error("no prompts") }
    override val history = testHistory()
    override val composerSession =
        ComposerSession(
            polisher,
            settings,
            apiKeyStore,
            history,
            CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        )
}

/** Robolectric creates one per test, so every test starts with fresh fakes. */
class TestApp : WritingAssistantApp() {
    override val graph = FakeAppGraph()
}
