package local.writingassistant.app.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import local.writingassistant.core.Channel
import local.writingassistant.core.HistoryEntry
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [36])
class HistoryScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val restored = mutableListOf<String>()
    private val deleted = mutableListOf<String>()
    private var cleared = 0
    private val actions =
        HistoryActions(
            onRestore = { restored += it },
            onDelete = { deleted += it },
            onClear = { cleared++ },
        )

    private fun entry(
        id: String,
        output: String,
        channel: Channel = Channel.SLACK,
    ) = HistoryEntry(
        id = id,
        epochSeconds = 1_700_000_000,
        channel = channel,
        input = "input $id",
        output = output,
        learningSummary = null,
        detectedLanguage = "en",
        wasTranslated = false,
        modelUsed = "fake",
    )

    private fun show(
        entries: List<HistoryEntry>,
        failure: String? = null,
    ) {
        compose.setContent {
            WritingAssistantTheme { HistoryScreen(entries, failure, actions) }
        }
    }

    @Test
    fun anEmptyHistorySaysSo() {
        show(emptyList())
        compose.onNodeWithText("Nothing here yet", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Clear all").assertDoesNotExist()
    }

    @Test
    fun rowsShowTheChannelAndTheFirstLineOfTheOutput() {
        show(
            listOf(
                entry("a", "\n**Hello** there\nsecond line", Channel.EMAIL),
                entry("b", "- a bullet"),
            ),
        )
        compose.onNodeWithText("Hello there").assertIsDisplayed()
        compose.onNodeWithText("second line", substring = true).assertDoesNotExist()
        compose.onNodeWithText("a bullet").assertIsDisplayed()
        compose.onNodeWithText(Channel.EMAIL.shortName, substring = true).assertIsDisplayed()
    }

    @Test
    fun tappingARowRestoresIt() {
        show(listOf(entry("a", "first"), entry("b", "second")))
        compose.onNodeWithText("second").performClick()
        assertEquals(listOf("b"), restored)
    }

    @Test
    fun deleteRemovesOnlyThatRow() {
        show(listOf(entry("a", "first"), entry("b", "second")))
        compose.onAllNodesWithText("Delete")[1].performClick()
        assertEquals(listOf("b"), deleted)
        assertEquals(emptyList<String>(), restored)
    }

    @Test
    fun clearAllAsksFirst() {
        show(listOf(entry("a", "first")))
        compose.onNodeWithText("Clear all").performClick()
        assertEquals(0, cleared)
        compose.onNodeWithText("Cancel").performClick()
        compose.onNodeWithText("Clear all").performClick()
        compose.onNodeWithText("Delete all").performClick()
        assertEquals(1, cleared)
    }

    @Test
    fun aFailureIsShown() {
        show(listOf(entry("a", "first")), failure = "Couldn't write history.json.")
        compose.onNodeWithText("Couldn't write history.json.").assertIsDisplayed()
    }

    @Test
    fun firstLineSkipsBlankLinesAndMarkers() {
        assertEquals("Title", firstLine("\n  \n# Title\nbody"))
        assertEquals("item", firstLine("* item"))
        assertEquals("", firstLine(" \n "))
    }
}
