package local.writingassistant.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import local.writingassistant.core.Channel
import local.writingassistant.core.Mode
import local.writingassistant.core.OutputLanguage
import local.writingassistant.core.Provider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.io.File

@RunWith(AndroidJUnit4::class)
@Config(sdk = [36])
class DataStoreAppSettingsTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val dataStore: DataStore<Preferences> by lazy {
        PreferenceDataStoreFactory.create(
            scope = scope,
        ) { File(folder.root, "settings.preferences_pb") }
    }
    private val settings by lazy { DataStoreAppSettings(dataStore) }

    @After
    fun tearDown() {
        scope.cancel()
    }

    @Test
    fun `the provider is Anthropic until one is chosen`() =
        runTest {
            assertEquals(Provider.ANTHROPIC, settings.provider())
        }

    @Test
    fun `every provider round-trips`() =
        runTest {
            for (provider in Provider.entries.reversed()) {
                settings.setProvider(provider)

                assertEquals(provider, settings.provider())
            }
        }

    @Test
    fun `an unknown stored provider id reads as Anthropic`() =
        runTest {
            dataStore.edit { it[stringPreferencesKey("provider")] = "carrier_pigeon" }

            assertEquals(Provider.ANTHROPIC, settings.provider())
        }

    @Test
    fun `the context constructor persists across instances`() =
        runTest {
            val context = ApplicationProvider.getApplicationContext<Context>()

            DataStoreAppSettings(context).setLastChannel(Mode.WORK, Channel.FORMAL)

            assertEquals(
                Channel.FORMAL,
                DataStoreAppSettings(context)
                    .modes
                    .first()
                    .work.lastChannel,
            )
        }

    @Test
    fun `new settings start with each mode's defaults and Writing Desk`() =
        runTest {
            val modes = settings.modes.first()

            assertEquals(Mode.WORK, modes.current)
            assertEquals(
                listOf(
                    Channel.SLACK,
                    Channel.SLACK_INFORMAL,
                    Channel.EMAIL,
                    Channel.TALKING_POINTS,
                    Channel.AI_PROMPT,
                    Channel.FORMAL,
                    Channel.PROOFREAD,
                ),
                modes.work.visibleChannels,
            )
            assertEquals(Channel.SLACK, modes.work.channel)
            assertEquals(OutputLanguage.ENGLISH, modes.work.outputLanguage)
            assertTrue(modes.work.learningSummary)
            assertEquals(
                listOf(Channel.PERSONAL_MESSAGE, Channel.EMAIL, Channel.PROOFREAD, Channel.OTHER),
                modes.personal.visibleChannels,
            )
            assertEquals(Channel.PERSONAL_MESSAGE, modes.personal.channel)
            assertEquals(OutputLanguage.SAME_AS_INPUT, modes.personal.outputLanguage)
            assertFalse(modes.personal.learningSummary)
            assertEquals(PalettePreset.WRITING_DESK, settings.palette.first())
        }

    @Test
    fun `each mode keeps its own settings`() =
        runTest {
            settings.setMode(Mode.PERSONAL)
            settings.setLastChannel(Mode.PERSONAL, Channel.EMAIL)
            settings.setOutputLanguage(Mode.WORK, OutputLanguage.SAME_AS_INPUT)
            settings.setLearningSummary(Mode.PERSONAL, true)

            val modes = settings.modes.first()
            assertEquals(Mode.PERSONAL, modes.current)
            assertEquals(Channel.EMAIL, modes.personal.lastChannel)
            assertEquals(Channel.SLACK, modes.work.lastChannel)
            assertEquals(OutputLanguage.SAME_AS_INPUT, modes.work.outputLanguage)
            assertEquals(OutputLanguage.SAME_AS_INPUT, modes.personal.outputLanguage)
            assertTrue(modes.personal.learningSummary)
            assertTrue(modes.work.learningSummary)
        }

    @Test
    fun `a shown channel goes to the end and a hidden one leaves`() =
        runTest {
            assertTrue(settings.setChannelVisible(Mode.PERSONAL, Channel.SLACK, visible = true))
            assertTrue(settings.setChannelVisible(Mode.PERSONAL, Channel.EMAIL, visible = false))

            assertEquals(
                listOf(Channel.PERSONAL_MESSAGE, Channel.PROOFREAD, Channel.OTHER, Channel.SLACK),
                settings.modes
                    .first()
                    .personal.visibleChannels,
            )
            assertEquals(
                ModeProfile.defaults(Mode.WORK).visibleChannels,
                settings.modes
                    .first()
                    .work.visibleChannels,
            )
        }

    @Test
    fun `the last visible channel can't be hidden`() =
        runTest {
            for (channel in listOf(Channel.EMAIL, Channel.PROOFREAD, Channel.OTHER)) {
                settings.setChannelVisible(Mode.PERSONAL, channel, visible = false)
            }

            assertFalse(
                settings.setChannelVisible(
                    Mode.PERSONAL,
                    Channel.PERSONAL_MESSAGE,
                    visible = false,
                ),
            )
            assertEquals(
                listOf(Channel.PERSONAL_MESSAGE),
                settings.modes
                    .first()
                    .personal.visibleChannels,
            )
        }

    @Test
    fun `a hidden last channel falls back to the first visible one`() =
        runTest {
            settings.setLastChannel(Mode.WORK, Channel.PERSONAL_MESSAGE)

            assertEquals(
                Channel.PERSONAL_MESSAGE,
                settings.modes
                    .first()
                    .work.lastChannel,
            )
            assertEquals(
                Channel.SLACK,
                settings.modes
                    .first()
                    .work.channel,
            )
        }

    @Test
    fun `unknown or damaged stored values read as the mode's defaults`() =
        runTest {
            dataStore.edit {
                it[stringPreferencesKey("mode")] = "family"
                it[stringPreferencesKey("work_visible_channels")] = "carrier_pigeon,,email,email"
                it[stringPreferencesKey("work_last_channel")] = "telegram"
                it[stringPreferencesKey("work_output_language")] = "klingon"
                it[stringPreferencesKey("personal_visible_channels")] = "nope"
            }

            val modes = settings.modes.first()
            assertEquals(Mode.WORK, modes.current)
            assertEquals(listOf(Channel.EMAIL), modes.work.visibleChannels)
            assertEquals(Channel.SLACK, modes.work.lastChannel)
            assertEquals(Channel.EMAIL, modes.work.channel)
            assertEquals(OutputLanguage.ENGLISH, modes.work.outputLanguage)
            assertEquals(ModeProfile.defaults(Mode.PERSONAL), modes.personal)
        }

    @Test
    fun `the old global keys are ignored`() =
        runTest {
            dataStore.edit {
                it[stringPreferencesKey("last_channel")] = "formal"
                it[stringSetPreferencesKey("disabled_channels")] = setOf("slack")
                it[booleanPreferencesKey("learning_summary")] = false
            }

            assertEquals(ModeSettings(), settings.modes.first())
        }

    @Test
    fun `every palette round-trips`() =
        runTest {
            for (palette in PalettePreset.entries.reversed()) {
                settings.setPalette(palette)

                assertEquals(palette, settings.palette.first())
            }
        }

    @Test
    fun `an unknown stored palette id reads as Writing Desk`() =
        runTest {
            dataStore.edit { it[stringPreferencesKey("palette")] = "neon" }

            assertEquals(PalettePreset.WRITING_DESK, settings.palette.first())
        }
}
