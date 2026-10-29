package local.writingassistant.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * The Writing Desk palette from `ThemePalette.swift`, one value per appearance, plus Android-only
 * control colours: `border` keeps field, button and chip outlines at 3:1 or more against paper,
 * and `inkWash` fills the selected channel chip.
 */
private object WritingDesk {
    val inkLight = Color(0xFF33378A)
    val inkDark = Color(0xFFA9ADF2)
    val paperLight = Color(0xFFFDFDFC)
    val paperDark = Color(0xFF1F2024)
    val deskLight = Color(0xFFEDEFF3)
    val deskDark = Color(0xFF141519)
    val ruleLight = Color(0xFFD9DCE3)
    val ruleDark = Color(0xFF34363D)
    val borderLight = Color(0xFF767A86)
    val borderDark = Color(0xFF8B8E99)
    val inkWashLight = Color(0xFFCBCDF2)
    val inkWashDark = Color(0xFF434785)
    val onInkWashLight = Color(0xFF1A1C55)
    val onInkWashDark = Color(0xFFE3E4FF)
    val redPencilLight = Color(0xFFB3263E)
    val redPencilDark = Color(0xFFFF8597)
    val marginGreenLight = Color(0xFF1D7A52)
    val marginGreenDark = Color(0xFF63D6A3)
}

private val lightScheme: ColorScheme =
    lightColorScheme(
        primary = WritingDesk.inkLight,
        onPrimary = WritingDesk.paperLight,
        secondary = WritingDesk.inkLight,
        onSecondary = WritingDesk.paperLight,
        secondaryContainer = WritingDesk.inkWashLight,
        onSecondaryContainer = WritingDesk.onInkWashLight,
        tertiary = WritingDesk.marginGreenLight,
        onTertiary = WritingDesk.paperLight,
        background = WritingDesk.deskLight,
        surface = WritingDesk.paperLight,
        surfaceContainer = WritingDesk.deskLight,
        surfaceContainerLow = WritingDesk.paperLight,
        outline = WritingDesk.borderLight,
        outlineVariant = WritingDesk.ruleLight,
        error = WritingDesk.redPencilLight,
        onError = WritingDesk.paperLight,
    )

private val darkScheme: ColorScheme =
    darkColorScheme(
        primary = WritingDesk.inkDark,
        onPrimary = WritingDesk.deskDark,
        secondary = WritingDesk.inkDark,
        onSecondary = WritingDesk.deskDark,
        secondaryContainer = WritingDesk.inkWashDark,
        onSecondaryContainer = WritingDesk.onInkWashDark,
        tertiary = WritingDesk.marginGreenDark,
        onTertiary = WritingDesk.deskDark,
        background = WritingDesk.deskDark,
        surface = WritingDesk.paperDark,
        surfaceContainer = WritingDesk.deskDark,
        surfaceContainerLow = WritingDesk.paperDark,
        outline = WritingDesk.borderDark,
        outlineVariant = WritingDesk.ruleDark,
        error = WritingDesk.redPencilDark,
        onError = WritingDesk.deskDark,
    )

/** Material 3 theme with the Writing Desk colours, following the system light/dark setting. */
@Composable
fun WritingAssistantTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) darkScheme else lightScheme,
        content = content,
    )
}
