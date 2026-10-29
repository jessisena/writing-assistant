package local.writingassistant.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
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
import local.writingassistant.core.Provider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
    fun `first run has no last channel`() =
        runTest {
            assertNull(settings.lastChannel())
        }

    @Test
    fun `every channel round-trips`() =
        runTest {
            for (channel in Channel.entries) {
                settings.setLastChannel(channel)

                assertEquals(channel, settings.lastChannel())
            }
        }

    @Test
    fun `an unknown stored channel id reads as null`() =
        runTest {
            dataStore.edit { it[stringPreferencesKey("last_channel")] = "carrier_pigeon" }

            assertNull(settings.lastChannel())
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

            DataStoreAppSettings(context).setLastChannel(Channel.FORMAL)

            assertEquals(Channel.FORMAL, DataStoreAppSettings(context).lastChannel())
        }

    @Test
    fun `new settings start with every channel, the summary on and Writing Desk`() =
        runTest {
            assertEquals(emptySet<Channel>(), settings.disabledChannels.first())
            assertTrue(settings.learningSummaryEnabled.first())
            assertEquals(PalettePreset.WRITING_DESK, settings.palette.first())
        }

    @Test
    fun `channels can be turned off and on again`() =
        runTest {
            settings.setChannelEnabled(Channel.EMAIL, enabled = false)
            settings.setChannelEnabled(Channel.FORMAL, enabled = false)
            assertEquals(setOf(Channel.EMAIL, Channel.FORMAL), settings.disabledChannels.first())

            settings.setChannelEnabled(Channel.EMAIL, enabled = true)
            settings.setChannelEnabled(Channel.SLACK, enabled = true)
            assertEquals(setOf(Channel.FORMAL), settings.disabledChannels.first())
        }

    @Test
    fun `unknown disabled channel ids are ignored`() =
        runTest {
            dataStore.edit {
                it[stringSetPreferencesKey("disabled_channels")] = setOf("carrier_pigeon", "email")
            }

            assertEquals(setOf(Channel.EMAIL), settings.disabledChannels.first())
        }

    @Test
    fun `the learning summary switch round-trips`() =
        runTest {
            settings.setLearningSummaryEnabled(false)
            assertFalse(settings.learningSummaryEnabled.first())

            settings.setLearningSummaryEnabled(true)
            assertTrue(settings.learningSummaryEnabled.first())
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
