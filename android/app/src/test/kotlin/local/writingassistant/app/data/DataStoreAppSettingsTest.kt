package local.writingassistant.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import local.writingassistant.core.Channel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
    fun `the context constructor persists across instances`() =
        runTest {
            val context = ApplicationProvider.getApplicationContext<Context>()

            DataStoreAppSettings(context).setLastChannel(Channel.FORMAL)

            assertEquals(Channel.FORMAL, DataStoreAppSettings(context).lastChannel())
        }
}
