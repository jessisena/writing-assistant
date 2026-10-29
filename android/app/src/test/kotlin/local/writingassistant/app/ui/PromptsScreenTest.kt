package local.writingassistant.app.ui

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.Dispatchers
import local.writingassistant.core.Channel
import local.writingassistant.core.PromptFile
import local.writingassistant.core.PromptOverrideStore
import local.writingassistant.core.PromptValidationException
import local.writingassistant.core.Refinement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.nio.file.Files

/**
 * The prompt list and editor. The editor tests use a real [PromptOverrideStore] in a temp
 * directory, with defaults that name the file they were read for.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [36])
class PromptsScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val store =
        PromptOverrideStore(Files.createTempDirectory("prompts").toFile()) { file ->
            "default for ${file.relativePath} ${PromptFile.CHANNEL_PLACEHOLDER}"
        }

    private fun edit(file: PromptFile) {
        val viewModel = PromptEditorViewModel(file, store, io = Dispatchers.Unconfined)
        compose.setContent {
            WritingAssistantTheme { PromptEditorScreen(viewModel) }
        }
    }

    @Test
    fun theListMarksEditedFilesAndOpensTheTappedOne() {
        val opened = mutableListOf<PromptFile>()
        val slack = PromptFile.ForChannel(Channel.SLACK)
        compose.setContent {
            WritingAssistantTheme { PromptListScreen(setOf(slack), { opened += it }) }
        }
        compose.onNodeWithText("Global rules").assertExists()
        compose.onAllNodesWithText("Edited").assertCountEquals(1)
        val shorter = PromptFile.ForRefinement(Refinement.SHORTER)
        compose.onNodeWithText(shorter.displayName).performScrollTo().performClick()
        assertEquals(listOf<PromptFile>(shorter), opened)
    }

    @Test
    fun theEditorShowsTheTextInEffect() {
        edit(PromptFile.Global)
        compose.onNodeWithText("default for polish.txt", substring = true).assertExists()
        compose.onNodeWithText("This is the bundled prompt.").assertExists()
        compose.onNodeWithText("Restore default").assertIsNotEnabled()
    }

    @Test
    fun savingGlobalRulesWithoutThePlaceholderShowsTheError() {
        edit(PromptFile.Global)
        compose.onNodeWithText("default for", substring = true).performTextReplacement("no slot")
        compose.onNodeWithText("Save").performScrollTo().performClick()
        compose.waitForIdle()
        compose
            .onNodeWithText(PromptValidationException.MissingPlaceholder.message)
            .assertExists()
        assertFalse(store.isCustomized(PromptFile.Global))
    }

    @Test
    fun savingStoresTheEdit() {
        val slack = PromptFile.ForChannel(Channel.SLACK)
        edit(slack)
        compose.onNodeWithText("default for", substring = true).performTextReplacement("mine")
        compose.onNodeWithText("Save").performScrollTo().performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Saved.").assertExists()
        assertEquals("mine", store.read(slack))
        assertTrue(store.isCustomized(slack))
    }

    @Test
    fun restoreDefaultAsksFirstThenDeletesTheEdit() {
        val slack = PromptFile.ForChannel(Channel.SLACK)
        store.save(slack, "mine")
        edit(slack)
        compose.onNodeWithText("Restore default").performScrollTo().performClick()
        assertTrue("restored before confirming", store.isCustomized(slack))
        compose.onNodeWithText("Keep edit").performScrollTo().performClick()
        compose.onNodeWithText("Restore default").performScrollTo().performClick()
        compose.onNodeWithText("Restore").performScrollTo().performClick()
        compose.waitForIdle()
        assertFalse(store.isCustomized(slack))
        compose.onNodeWithText("default for channels/slack.txt", substring = true).assertExists()
        compose.onNodeWithText("Default restored.").assertExists()
    }
}
