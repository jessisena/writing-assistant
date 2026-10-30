package local.writingassistant.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import local.writingassistant.app.data.ModeProfile
import local.writingassistant.app.data.ModeSettings
import local.writingassistant.app.data.PalettePreset
import local.writingassistant.core.Channel
import local.writingassistant.core.Mode
import local.writingassistant.core.OutputLanguage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [36])
class PreferencesTest {
    @get:Rule
    val compose = createComposeRule()

    private val settings = FakeAppSettings()
    private val viewModel = PreferencesViewModel(settings)
    private var promptsOpened = 0

    private fun show() {
        compose.setContent {
            WritingAssistantTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    PreferencesSection(viewModel, onOpenPrompts = { promptsOpened++ })
                }
            }
        }
    }

    @Test
    fun turningAChannelOffStoresItForTheCurrentMode() {
        show()
        val row = compose.onNodeWithText(Channel.EMAIL.displayName).performScrollTo()
        row.assertIsOn().performClick()
        compose.waitForIdle()
        assertFalse(Channel.EMAIL in settings.modes.value.work.visibleChannels)
        assertTrue(Channel.EMAIL in settings.modes.value.personal.visibleChannels)
        compose.onNodeWithText(Channel.EMAIL.displayName).assertIsOff()
    }

    @Test
    fun turningAChannelOnAppendsIt() {
        show()
        val row = compose.onNodeWithText(Channel.OTHER.displayName).performScrollTo()
        row.assertIsOff().performClick()
        compose.waitForIdle()
        assertEquals(
            Channel.OTHER,
            settings.modes.value.work.visibleChannels
                .last(),
        )
    }

    @Test
    fun thePersonalTabEditsPersonalMode() {
        show()
        compose.onNodeWithText("Personal").performScrollTo().performClick()
        compose.onNodeWithText(Channel.PERSONAL_MESSAGE.displayName).performScrollTo().assertIsOn()
        compose
            .onNodeWithText(
                Channel.SLACK.displayName,
            ).performScrollTo()
            .assertIsOff()
            .performClick()
        compose.onNodeWithText("English").performScrollTo().performClick()
        compose.waitForIdle()
        val personal = settings.modes.value.personal
        assertTrue(Channel.SLACK in personal.visibleChannels)
        assertEquals(OutputLanguage.ENGLISH, personal.outputLanguage)
        assertEquals(Mode.WORK, settings.modes.value.current)
    }

    @Test
    fun theLastVisibleChannelCantBeTurnedOff() {
        val onlySlack =
            ModeProfile
                .defaults(
                    Mode.WORK,
                ).copy(visibleChannels = listOf(Channel.SLACK))
        settings.modes.value = ModeSettings(work = onlySlack)
        show()
        compose.onNodeWithText(Channel.SLACK.displayName).performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText(Channel.EMAIL.displayName).performScrollTo().assertIsEnabled()
        viewModel.setChannelVisible(Channel.SLACK, false)
        compose.waitForIdle()
        assertEquals(listOf(Channel.SLACK), settings.modes.value.work.visibleChannels)
    }

    @Test
    fun theLearningSummarySwitchStoresTheChoiceForTheMode() {
        show()
        compose.onNodeWithText("English learning summary").performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals(false, settings.modes.value.work.learningSummary)
        compose.onNodeWithText("faster", substring = true).performScrollTo()
    }

    @Test
    fun choosingAPaletteStoresIt() {
        show()
        compose.onNodeWithText(PalettePreset.SEPIA.displayName).performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals(PalettePreset.SEPIA, settings.palette.value)
    }

    @Test
    fun thePromptsRowOpensThePromptList() {
        show()
        compose.onNodeWithText("Prompts").performScrollTo().performClick()
        assertTrue(promptsOpened == 1)
    }
}
