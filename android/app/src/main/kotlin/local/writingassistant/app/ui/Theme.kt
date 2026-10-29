package local.writingassistant.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import local.writingassistant.app.data.PalettePreset

/**
 * One appearance of a palette: the six colours from `ThemePalette.swift` plus Android-only control
 * colours. [border] keeps field, button and chip outlines at 3:1 or more against paper, and
 * [inkWash] fills the selected channel chip under [onInkWash] text.
 */
internal data class Swatch(
    val ink: Color,
    val paper: Color,
    val desk: Color,
    val rule: Color,
    val border: Color,
    val inkWash: Color,
    val onInkWash: Color,
    val redPencil: Color,
    val marginGreen: Color,
)

private val writingDeskLight =
    Swatch(
        ink = Color(0xFF33378A),
        paper = Color(0xFFFDFDFC),
        desk = Color(0xFFEDEFF3),
        rule = Color(0xFFD9DCE3),
        border = Color(0xFF767A86),
        inkWash = Color(0xFFCBCDF2),
        onInkWash = Color(0xFF1A1C55),
        redPencil = Color(0xFFB3263E),
        marginGreen = Color(0xFF1D7A52),
    )

private val writingDeskDark =
    Swatch(
        ink = Color(0xFFA9ADF2),
        paper = Color(0xFF1F2024),
        desk = Color(0xFF141519),
        rule = Color(0xFF34363D),
        border = Color(0xFF8B8E99),
        inkWash = Color(0xFF434785),
        onInkWash = Color(0xFFE3E4FF),
        redPencil = Color(0xFFFF8597),
        marginGreen = Color(0xFF63D6A3),
    )

private val lagoonLight =
    Swatch(
        ink = Color(0xFF025F67),
        paper = Color(0xFFF7F6F2),
        desk = Color(0xFFE4E8EA),
        rule = Color(0xFFBCC5CC),
        border = Color(0xFF6B7A80),
        inkWash = Color(0xFFBFE3DF),
        onInkWash = Color(0xFF01373C),
        redPencil = Color(0xFFB8463A),
        marginGreen = Color(0xFF2F9D94),
    )

private val lagoonDark =
    Swatch(
        ink = Color(0xFF6FCFC6),
        paper = Color(0xFF0B2A45),
        desk = Color(0xFF041F35),
        rule = Color(0xFF24435C),
        border = Color(0xFF6E8CA3),
        inkWash = Color(0xFF1D5A66),
        onInkWash = Color(0xFFD8F4F1),
        redPencil = Color(0xFFFF8F80),
        marginGreen = Color(0xFF63D6C8),
    )

private val sepiaLight =
    Swatch(
        ink = Color(0xFF8A4B1F),
        paper = Color(0xFFFBF6EC),
        desk = Color(0xFFEFE6D6),
        rule = Color(0xFFDCCFB8),
        border = Color(0xFF8A7A66),
        inkWash = Color(0xFFF0D9C2),
        onInkWash = Color(0xFF4A2810),
        redPencil = Color(0xFFA8322A),
        marginGreen = Color(0xFF4D7A2A),
    )

private val sepiaDark =
    Swatch(
        ink = Color(0xFFE8B07F),
        paper = Color(0xFF2A241D),
        desk = Color(0xFF1C1813),
        rule = Color(0xFF433A2E),
        border = Color(0xFF9A8A76),
        inkWash = Color(0xFF5E432B),
        onInkWash = Color(0xFFFCE7D3),
        redPencil = Color(0xFFFF8C7A),
        marginGreen = Color(0xFF9CD67A),
    )

private fun Swatch.lightScheme(): ColorScheme =
    lightColorScheme(
        primary = ink,
        onPrimary = paper,
        secondary = ink,
        onSecondary = paper,
        secondaryContainer = inkWash,
        onSecondaryContainer = onInkWash,
        tertiary = marginGreen,
        onTertiary = paper,
        background = desk,
        surface = paper,
        surfaceContainer = desk,
        surfaceContainerLow = paper,
        outline = border,
        outlineVariant = rule,
        error = redPencil,
        onError = paper,
    )

private fun Swatch.darkScheme(): ColorScheme =
    darkColorScheme(
        primary = ink,
        onPrimary = desk,
        secondary = ink,
        onSecondary = desk,
        secondaryContainer = inkWash,
        onSecondaryContainer = onInkWash,
        tertiary = marginGreen,
        onTertiary = desk,
        background = desk,
        surface = paper,
        surfaceContainer = desk,
        surfaceContainerLow = paper,
        outline = border,
        outlineVariant = rule,
        error = redPencil,
        onError = desk,
    )

private val writingDeskSchemes = writingDeskLight.lightScheme() to writingDeskDark.darkScheme()
private val lagoonSchemes = lagoonLight.lightScheme() to lagoonDark.darkScheme()
private val sepiaSchemes = sepiaLight.lightScheme() to sepiaDark.darkScheme()

/** The fixed colours of [preset] for one appearance; null for [PalettePreset.SYSTEM]. */
internal fun staticColorScheme(
    preset: PalettePreset,
    dark: Boolean,
): ColorScheme? {
    val schemes =
        when (preset) {
            PalettePreset.WRITING_DESK -> writingDeskSchemes
            PalettePreset.LAGOON -> lagoonSchemes
            PalettePreset.SEPIA -> sepiaSchemes
            PalettePreset.SYSTEM -> return null
        }
    return if (dark) schemes.second else schemes.first
}

/**
 * Material 3 theme with [palette]'s colours, following the system light/dark setting.
 * [PalettePreset.SYSTEM] takes Material You colours from the wallpaper.
 */
@Composable
fun WritingAssistantTheme(
    palette: PalettePreset = PalettePreset.WRITING_DESK,
    content: @Composable () -> Unit,
) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val scheme =
        staticColorScheme(palette, dark)
            ?: if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    MaterialTheme(colorScheme = scheme, content = content)
}

/**
 * [WritingAssistantTheme] with the palette from [palette], typically `AppSettings.palette`.
 * Renders nothing until the first value arrives, so a chosen palette doesn't flash the default.
 */
@Composable
fun SavedPaletteTheme(
    palette: Flow<PalettePreset>,
    content: @Composable () -> Unit,
) {
    val nullable = remember(palette) { palette.map<PalettePreset, PalettePreset?> { it } }
    val current by nullable.collectAsStateWithLifecycle(initialValue = null)
    current?.let { WritingAssistantTheme(it, content) }
}

/** Border for outlined buttons; Material 3's default uses the pale divider colour. */
@Composable
fun outlinedButtonBorder(enabled: Boolean): BorderStroke {
    val outline = MaterialTheme.colorScheme.outline
    return BorderStroke(1.dp, if (enabled) outline else outline.copy(alpha = DISABLED_BORDER_ALPHA))
}

/** Material 3's alpha for a disabled outlined button's border. */
private const val DISABLED_BORDER_ALPHA = 0.12f
