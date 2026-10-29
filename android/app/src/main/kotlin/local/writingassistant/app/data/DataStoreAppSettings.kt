package local.writingassistant.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import local.writingassistant.core.Channel

private val Context.settingsDataStore by preferencesDataStore(name = "settings")

/** [AppSettings] persisted in Preferences DataStore. */
class DataStoreAppSettings internal constructor(
    private val dataStore: DataStore<Preferences>,
) : AppSettings {
    constructor(context: Context) : this(context.applicationContext.settingsDataStore)

    override suspend fun lastChannel(): Channel? =
        dataStore.data.first()[LAST_CHANNEL]?.let(Channel::fromId)

    override suspend fun setLastChannel(channel: Channel) {
        dataStore.edit { it[LAST_CHANNEL] = channel.id }
    }

    private companion object {
        val LAST_CHANNEL = stringPreferencesKey("last_channel")
    }
}
