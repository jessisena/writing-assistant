package local.writingassistant.app.intents

import android.app.Activity
import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.awaitCancellation
import local.writingassistant.app.ui.ComposerEvent
import local.writingassistant.app.ui.ComposerState
import local.writingassistant.app.ui.FakePolishing
import local.writingassistant.core.Refinement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [36], application = TestApp::class)
class SheetActivitiesTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val app: TestApp = ApplicationProvider.getApplicationContext()

    private fun processText(
        text: CharSequence?,
        readOnly: Boolean = false,
    ): Intent =
        Intent(app, ProcessTextActivity::class.java)
            .setAction(Intent.ACTION_PROCESS_TEXT)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_PROCESS_TEXT, text)
            .putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, readOnly)

    private fun share(text: String?): Intent =
        Intent(app, ShareActivity::class.java)
            .setAction(Intent.ACTION_SEND)
            .setType("text/plain")
            .apply { if (text != null) putExtra(Intent.EXTRA_TEXT, text) }

    private fun <A : Activity> assertClosed(scenario: ActivityScenario<A>) {
        scenario.onActivity { assertTrue(it.isFinishing) }
    }

    private fun polish() {
        compose.onNodeWithText("Polish").performClick()
        compose.waitForIdle()
    }

    @Test
    fun processTextPrefillsTheInputAndOffersReplace() {
        ActivityScenario.launch<ProcessTextActivity>(processText("hey can u check")).use {
            compose.onNodeWithText("hey can u check").assertExists()
            polish()
            compose.onNodeWithText("Replace").performScrollTo()
        }
    }

    @Test
    fun replaceReturnsThePolishedPlainText() {
        app.graph.polisher.onPolish = { FakePolishing.result(it).copy(polishedText = "**Hey**") }
        val scenario =
            ActivityScenario.launchActivityForResult<ProcessTextActivity>(
                processText("hey"),
            )
        polish()
        compose.onNodeWithText("Replace").performScrollTo().performClick()
        assertEquals(Activity.RESULT_OK, scenario.result.resultCode)
        assertEquals(
            "Hey",
            scenario.result.resultData.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT),
        )
        assertClosed(scenario)
    }

    @Test
    fun readOnlySelectionHidesReplace() {
        ActivityScenario.launch<ProcessTextActivity>(processText("hey", readOnly = true)).use {
            polish()
            compose.onNodeWithText("Copy").performScrollTo()
            compose.onNodeWithText("Replace").assertDoesNotExist()
        }
    }

    @Test
    fun missingProcessTextOpensAnEmptyComposer() {
        ActivityScenario.launch<ProcessTextActivity>(processText(null)).use {
            compose.onNodeWithText("Polish").assertIsNotEnabled()
        }
    }

    @Test
    fun sharePrefillsTheInputAndOffersCopyOnly() {
        ActivityScenario.launch<ShareActivity>(share("hello")).use {
            compose.onNodeWithText("hello").assertExists()
            polish()
            compose.onNodeWithText("Copy").performScrollTo()
            compose.onNodeWithText("Replace").assertDoesNotExist()
        }
    }

    @Test
    fun copyFillsTheClipboardAndCloses() {
        val scenario = ActivityScenario.launch<ShareActivity>(share("hello"))
        polish()
        compose.onNodeWithText("Copy").performScrollTo().performClick()
        val clip = app.getSystemService(ClipboardManager::class.java).primaryClip
        assertEquals("polished: hello", clip?.getItemAt(0)?.text?.toString())
        assertClosed(scenario)
    }

    @Test
    fun shareWithoutTextOpensAnEmptyComposer() {
        ActivityScenario.launch<ShareActivity>(share(null)).use {
            compose.onNodeWithText("Polish").assertIsNotEnabled()
        }
    }

    @Test
    fun missingKeyAsksForItThenReturnsToTheComposer() {
        app.graph.apiKeyStore.key = null
        ActivityScenario.launch<ShareActivity>(share("hello")).use {
            // Replace, not append: debug builds prefill the field from local.properties.
            compose.onNodeWithText("Anthropic API key").performTextReplacement("sk-ant-test")
            compose.onNodeWithText("Save").performClick()
            compose.waitForIdle()
            assertTrue("the typed key was not stored", app.graph.apiKeyStore.key == "sk-ant-test")
            polish()
            compose.onNodeWithText("polished: hello").assertExists()
        }
    }

    @Test
    fun theInputIsNotReloadedAfterRecreation() {
        ActivityScenario.launch<ShareActivity>(share("hello")).use { scenario ->
            compose.onNodeWithText("hello").performTextReplacement("edited")
            scenario.recreate()
            compose.onNodeWithText("edited").assertExists()
        }
    }

    @Test
    fun blankShareKeepsTheRunningSession() {
        val session = app.graph.composerSession
        session.onEvent(ComposerEvent.Open("draft"))
        session.onEvent(ComposerEvent.Polish)
        app.graph.polisher.onRefine = { _, _ -> awaitCancellation() }
        session.onEvent(ComposerEvent.Refine(Refinement.entries.first()))
        for (blank in listOf(null, "", "  \n")) {
            ActivityScenario.launch<ShareActivity>(share(blank)).use {
                compose.onNodeWithText("draft").assertExists()
            }
            val state = session.state.value
            assertEquals("draft", state.input)
            assertEquals("polished: draft", state.output)
            assertTrue("the refinement was cancelled", state.phase is ComposerState.Phase.Working)
        }
    }

    @Test
    fun theTextIsLoadedAgainAfterProcessDeath() {
        val savedBeforeDeath = Bundle()
        Robolectric.buildActivity(ShareActivity::class.java, share("hello")).use {
            it.setup(savedBeforeDeath)
            compose.onNodeWithText("hello").assertExists()
        }
    }
}
