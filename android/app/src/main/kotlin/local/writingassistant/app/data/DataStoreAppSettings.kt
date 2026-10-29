package local.writingassistant.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import local.writingassistant.core.Channel
import local.writingassistant.core.Provider

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

    override suspend fun provider(): Provider =
        dataStore.data.first()[PROVIDER]?.let(Provider::fromId) ?: Provider.ANTHROPIC

    override suspend fun setProvider(provider: Provider) {
        dataStore.edit { it[PROVIDER] = provider.id }
    }

    /** Unknown ids (a channel removed in a later version) are dropped. */
    override val disabledChannels: Flow<Set<Channel>> =
        dataStore.data
            .map { prefs -> prefs[DISABLED_CHANNELS].orEmpty().mapNotNull(Channel::fromId).toSet() }
            .distinctUntilChanged()

    override suspend fun setChannelEnabled(
        channel: Channel,
        enabled: Boolean,
    ) {
        dataStore.edit {
            val current = it[DISABLED_CHANNELS].orEmpty()
            it[DISABLED_CHANNELS] = if (enabled) current - channel.id else current + channel.id
        }
    }

    override val learningSummaryEnabled: Flow<Boolean> =
        dataStore.data.map { it[LEARNING_SUMMARY] ?: true }.distinctUntilChanged()

    override suspend fun setLearningSummaryEnabled(enabled: Boolean) {
        dataStore.edit { it[LEARNING_SUMMARY] = enabled }
    }

    override val palette: Flow<PalettePreset> =
        dataStore.data
            .map { prefs ->
                prefs[PALETTE]?.let(PalettePreset::fromId) ?: PalettePreset.WRITING_DESK
            }.distinctUntilChanged()

    override suspend fun setPalette(palette: PalettePreset) {
        dataStore.edit { it[PALETTE] = palette.id }
    }

    private companion object {
        val LAST_CHANNEL = stringPreferencesKey("last_channel")
        val PROVIDER = stringPreferencesKey("provider")
        val DISABLED_CHANNELS = stringSetPreferencesKey("disabled_channels")
        val LEARNING_SUMMARY = booleanPreferencesKey("learning_summary")
        val PALETTE = stringPreferencesKey("palette")
    }
}
