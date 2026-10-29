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
import local.writingassistant.app.data.PalettePreset
import local.writingassistant.core.Channel
import org.junit.Assert.assertEquals
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
    fun turningAChannelOffStoresIt() {
        show()
        val row = compose.onNodeWithText(Channel.EMAIL.displayName).performScrollTo()
        row.assertIsOn().performClick()
        compose.waitForIdle()
        assertEquals(setOf(Channel.EMAIL), settings.disabledChannels.value)
        compose.onNodeWithText(Channel.EMAIL.displayName).assertIsOff()
    }

    @Test
    fun turningAChannelBackOnStoresIt() {
        settings.disabledChannels.value = setOf(Channel.FORMAL)
        show()
        val row = compose.onNodeWithText(Channel.FORMAL.displayName).performScrollTo()
        row.assertIsOff().performClick()
        compose.waitForIdle()
        assertEquals(emptySet<Channel>(), settings.disabledChannels.value)
    }

    @Test
    fun theLastEnabledChannelCantBeTurnedOff() {
        val allButSlack = Channel.entries.toSet() - Channel.SLACK
        settings.disabledChannels.value = allButSlack
        show()
        compose.onNodeWithText(Channel.SLACK.displayName).performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText(Channel.EMAIL.displayName).performScrollTo().assertIsEnabled()
        viewModel.setChannelEnabled(Channel.SLACK, false)
        compose.waitForIdle()
        assertEquals(allButSlack, settings.disabledChannels.value)
    }

    @Test
    fun theLearningSummarySwitchStoresTheChoice() {
        show()
        compose.onNodeWithText("English learning summary").performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals(false, settings.learningSummaryEnabled.value)
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
