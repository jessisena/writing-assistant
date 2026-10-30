package local.writingassistant.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import local.writingassistant.core.Channel
import local.writingassistant.core.Mode
import local.writingassistant.core.OutputLanguage
import local.writingassistant.core.Provider

private val Context.settingsDataStore by preferencesDataStore(name = "settings")

/**
 * [AppSettings] persisted in Preferences DataStore.
 *
 * The mode settings use `mode` (a [Mode] id) and, per mode, `<mode>_visible_channels` (channel
 * ids in chip order, comma-separated), `<mode>_last_channel`, `<mode>_output_language` (an
 * [OutputLanguage] id) and `<mode>_learning_summary`. A missing or unreadable value takes the
 * mode's default: unknown ids are dropped, and a list that keeps no channel takes the default
 * list.
 */
class DataStoreAppSettings internal constructor(
    private val dataStore: DataStore<Preferences>,
) : AppSettings {
    constructor(context: Context) : this(context.applicationContext.settingsDataStore)

    override suspend fun provider(): Provider =
        dataStore.data.first()[PROVIDER]?.let(Provider::fromId) ?: Provider.ANTHROPIC

    override suspend fun setProvider(provider: Provider) {
        dataStore.edit { it[PROVIDER] = provider.id }
    }

    override val modes: Flow<ModeSettings> =
        dataStore.data.map(::readModes).distinctUntilChanged()

    override suspend fun setMode(mode: Mode) {
        dataStore.edit { it[CURRENT_MODE] = mode.id }
    }

    override suspend fun setLastChannel(
        mode: Mode,
        channel: Channel,
    ) {
        dataStore.edit { it[ModeKeys(mode).lastChannel] = channel.id }
    }

    override suspend fun setChannelVisible(
        mode: Mode,
        channel: Channel,
        visible: Boolean,
    ): Boolean {
        var changed = false
        dataStore.edit { prefs ->
            val updated = readProfile(prefs, mode).withVisible(channel, visible) ?: return@edit
            changed = true
            writeChannels(prefs, mode, updated.visibleChannels)
        }
        return changed
    }

    override suspend fun setOutputLanguage(
        mode: Mode,
        language: OutputLanguage,
    ) {
        dataStore.edit { it[ModeKeys(mode).outputLanguage] = language.id }
    }

    override suspend fun setLearningSummary(
        mode: Mode,
        enabled: Boolean,
    ) {
        dataStore.edit { it[ModeKeys(mode).learningSummary] = enabled }
    }

    override val palette: Flow<PalettePreset> =
        dataStore.data
            .map { prefs ->
                prefs[PALETTE]?.let(PalettePreset::fromId) ?: PalettePreset.WRITING_DESK
            }.distinctUntilChanged()

    override suspend fun setPalette(palette: PalettePreset) {
        dataStore.edit { it[PALETTE] = palette.id }
    }

    /** The preference keys of one mode. */
    private class ModeKeys(
        mode: Mode,
    ) {
        val visibleChannels = stringPreferencesKey("${mode.id}_visible_channels")
        val lastChannel = stringPreferencesKey("${mode.id}_last_channel")
        val outputLanguage = stringPreferencesKey("${mode.id}_output_language")
        val learningSummary = booleanPreferencesKey("${mode.id}_learning_summary")
    }

    private companion object {
        val PROVIDER = stringPreferencesKey("provider")
        val PALETTE = stringPreferencesKey("palette")
        val CURRENT_MODE = stringPreferencesKey("mode")
        const val SEPARATOR = ","

        fun readModes(prefs: Preferences): ModeSettings =
            ModeSettings(
                current = prefs[CURRENT_MODE]?.let(Mode::fromId) ?: Mode.WORK,
                work = readProfile(prefs, Mode.WORK),
                personal = readProfile(prefs, Mode.PERSONAL),
            )

        /** The stored values over [mode]'s defaults. */
        fun readProfile(
            prefs: Preferences,
            mode: Mode,
        ): ModeProfile {
            val keys = ModeKeys(mode)
            val fallback = ModeProfile.defaults(mode)
            val channels =
                prefs[keys.visibleChannels]
                    ?.split(SEPARATOR)
                    ?.mapNotNull(Channel::fromId)
                    ?.distinct()
                    .orEmpty()
            return ModeProfile(
                visibleChannels = channels.ifEmpty { fallback.visibleChannels },
                lastChannel = prefs[keys.lastChannel]?.let(Channel::fromId) ?: fallback.lastChannel,
                outputLanguage =
                    prefs[keys.outputLanguage]?.let(OutputLanguage::fromId)
                        ?: fallback.outputLanguage,
                learningSummary = prefs[keys.learningSummary] ?: fallback.learningSummary,
            )
        }

        fun writeChannels(
            prefs: MutablePreferences,
            mode: Mode,
            channels: List<Channel>,
        ) {
            prefs[ModeKeys(mode).visibleChannels] = channels.joinToString(SEPARATOR) { it.id }
        }
    }
}
