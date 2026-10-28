package local.writingassistant.app.intents

import android.app.Activity
import android.content.ClipboardManager
import android.content.Intent
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
import local.writingassistant.app.ui.FakePolishing
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
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
            compose.onNodeWithText("Anthropic API key").performTextInput("sk-ant-test")
            compose.onNodeWithText("Save").performClick()
            compose.waitForIdle()
            assertEquals("sk-ant-test", app.graph.apiKeyStore.key)
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
}
