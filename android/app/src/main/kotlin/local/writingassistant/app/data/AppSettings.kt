package local.writingassistant.app.data

import kotlinx.coroutines.flow.Flow
import local.writingassistant.core.Channel
import local.writingassistant.core.Mode
import local.writingassistant.core.OutputLanguage
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
    /** The provider that handles requests. [Provider.ANTHROPIC] until the user picks another. */
    suspend fun provider(): Provider

    suspend fun setProvider(provider: Provider)

    /**
     * The current mode and each mode's channels, language and learning summary setting; each
     * mode starts with [ModeProfile.defaults].
     */
    val modes: Flow<ModeSettings>

    suspend fun setMode(mode: Mode)

    /** Remembers [channel] as [mode]'s last channel. */
    suspend fun setLastChannel(
        mode: Mode,
        channel: Channel,
    )

    /**
     * Shows [channel] (at the end of the chips) or hides it in [mode]. Hiding the mode's only
     * visible channel is refused and changes nothing.
     *
     * @return False when the change was refused.
     */
    suspend fun setChannelVisible(
        mode: Mode,
        channel: Channel,
        visible: Boolean,
    ): Boolean

    suspend fun setOutputLanguage(
        mode: Mode,
        language: OutputLanguage,
    )

    /** Whether [mode]'s English texts get a learning summary. */
    suspend fun setLearningSummary(
        mode: Mode,
        enabled: Boolean,
    )

    /** The app's colours. [PalettePreset.WRITING_DESK] until the user picks another. */
    val palette: Flow<PalettePreset>

    suspend fun setPalette(palette: PalettePreset)
}
