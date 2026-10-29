package local.writingassistant.app.ui

import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import local.writingassistant.app.MainActivity
import local.writingassistant.app.intents.TestApp
import local.writingassistant.core.Channel
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [36], application = TestApp::class)
class MainNavigationTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val app: TestApp = ApplicationProvider.getApplicationContext()

    private fun back(scenario: ActivityScenario<MainActivity>) {
        scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
        compose.waitForIdle()
    }

    @Test
    fun tappingAHistoryEntryRestoresItIntoTheComposer() {
        runBlocking {
            app.graph.history.record(FakePolishing.result("old"), "old input", Channel.EMAIL)
        }
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.onNodeWithText("History").performClick()
            compose.onNodeWithText("polished: old").performClick()
            compose.waitForIdle()
            compose.onNodeWithText("old input").assertExists()
            assertEquals(Channel.EMAIL, app.graph.composerSession.state.value.channel)
        }
    }

    @Test
    fun backGoesUpOneLevel() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            compose.onNodeWithText("Settings").performClick()
            compose.onNodeWithText("Prompts").performScrollTo().performClick()
            compose.onNodeWithText("Global rules").assertExists()
            back(scenario)
            compose.onNodeWithText("AI provider").assertExists()
            back(scenario)
            compose.onNodeWithText("Polish").assertExists()
        }
    }

    @Test
    fun reopeningAPromptDropsTheUnsavedEdit() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            compose.onNodeWithText("Settings").performClick()
            compose.onNodeWithText("Prompts").performScrollTo().performClick()
            compose.onNodeWithText("Global rules").performClick()
            compose.waitForIdle()
            compose.onNode(hasSetTextAction()).performTextReplacement("unsaved edit")
            back(scenario)
            compose.onNodeWithText("Global rules").performClick()
            compose.waitForIdle()

            compose.onNodeWithText("default polish.txt").assertExists()
            compose.onNodeWithText("unsaved edit").assertDoesNotExist()
        }
    }
}
