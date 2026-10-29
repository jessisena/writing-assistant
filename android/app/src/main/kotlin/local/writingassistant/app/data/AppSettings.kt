package local.writingassistant.app.data

import kotlinx.coroutines.flow.Flow
import local.writingassistant.core.Channel
import local.writingassistant.core.Provider

/** The colour palettes offered in Settings; the colours themselves live in `ui/Theme.kt`. */
enum class PalettePreset(
    /** Stable identifier used in storage; never change it. */
    val id: String,
    val displayName: String,
) {
    WRITING_DESK("writing_desk", "Writing Desk"),
    LAGOON("lagoon", "Lagoon"),
    SEPIA("sepia", "Sepia"),

    /** Material You colours taken from the wallpaper. */
    SYSTEM("system", "System (wallpaper)"),
    ;

    companion object {
        fun fromId(id: String): PalettePreset? = entries.firstOrNull { it.id == id }
    }
}

/** Small user preferences that aren't secret. */
interface AppSettings {
    /** The channel used last, preselected in the composer. Null on first run. */
    suspend fun lastChannel(): Channel?

    suspend fun setLastChannel(channel: Channel)

    /** The provider that handles requests. [Provider.ANTHROPIC] until the user picks another. */
    suspend fun provider(): Provider

    suspend fun setProvider(provider: Provider)

    /** Channels hidden from the composer; empty until the user turns one off. */
    val disabledChannels: Flow<Set<Channel>>

    suspend fun setChannelEnabled(
        channel: Channel,
        enabled: Boolean,
    )

    /** Whether English texts get a learning summary. True until the user turns it off. */
    val learningSummaryEnabled: Flow<Boolean>

    suspend fun setLearningSummaryEnabled(enabled: Boolean)

    /** The app's colours. [PalettePreset.WRITING_DESK] until the user picks another. */
    val palette: Flow<PalettePreset>

    suspend fun setPalette(palette: PalettePreset)
}
