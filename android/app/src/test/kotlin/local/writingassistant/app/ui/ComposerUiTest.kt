package local.writingassistant.app.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import local.writingassistant.core.Correction
import local.writingassistant.core.LearningSummary
import local.writingassistant.core.PolishError
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [36])
class ComposerUiTest {
    @get:Rule
    val compose = createComposeRule()

    private val summary =
        LearningSummary(corrections = listOf(Correction("tomorow", "tomorrow", "Spelling.")))
    private val polished =
        ComposerState(
            input = "hey",
            result = FakePolishing.result("hey").copy(learningSummary = summary),
            output = "polished: **hey**",
        )

    private fun show(
        state: ComposerState,
        onReplace: (() -> Unit)? = null,
        events: MutableList<ComposerEvent> = mutableListOf(),
    ) {
        compose.setContent {
            WritingAssistantTheme {
                Composer(state, { events += it }, onCopy = {}, onReplace = onReplace)
            }
        }
    }

    @Test
    fun replaceIsHiddenWithoutAHandler() {
        show(polished)
        compose.onNodeWithText("Copy").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Replace").assertDoesNotExist()
    }

    @Test
    fun replaceIsShownWithAHandler() {
        var replaced = false
        show(polished, onReplace = { replaced = true })
        compose.onNodeWithText("Replace").performScrollTo().performClick()
        assertEquals(true, replaced)
    }

    @Test
    fun polishIsDisabledForBlankInput() {
        show(ComposerState(input = " "))
        compose.onNodeWithText("Polish").assertIsNotEnabled()
    }

    @Test
    fun polishSendsTheEvent() {
        val events = mutableListOf<ComposerEvent>()
        show(ComposerState(input = "hey"), events = events)
        compose.onNodeWithText("Polish").assertIsEnabled().performClick()
        assertEquals(listOf<ComposerEvent>(ComposerEvent.Polish), events)
    }

    @Test
    fun resultIsRenderedWithoutMarkdownMarkers() {
        show(polished)
        compose.onNodeWithText("polished: hey").assertIsDisplayed()
    }

    @Test
    fun learningSummaryIsCollapsedUntilTapped() {
        show(polished)
        compose.onNodeWithText("tomorow → tomorrow").assertDoesNotExist()
        compose
            .onNodeWithText("What changed (1 tip)", substring = true)
            .performScrollTo()
            .performClick()
        compose.onNodeWithText("tomorow → tomorrow").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun errorBannerOffersRetry() {
        val events = mutableListOf<ComposerEvent>()
        show(polished.copy(error = PolishError.Overloaded), events = events)
        compose.onNodeWithText(PolishError.Overloaded.message).assertIsDisplayed()
        compose.onNodeWithText("Retry").performClick()
        assertEquals(listOf<ComposerEvent>(ComposerEvent.Retry), events)
    }

    @Test
    fun workingShowsCancel() {
        val events = mutableListOf<ComposerEvent>()
        show(polished.copy(phase = ComposerState.Phase.Working(null)), events = events)
        compose.onNodeWithText("Polish").assertDoesNotExist()
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(listOf<ComposerEvent>(ComposerEvent.Cancel), events)
    }
}
