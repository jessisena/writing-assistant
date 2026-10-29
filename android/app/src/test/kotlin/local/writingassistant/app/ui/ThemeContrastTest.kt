package local.writingassistant.app.ui

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import local.writingassistant.app.data.PalettePreset
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** WCAG 2 contrast checks for every fixed palette in both appearances. */
class ThemeContrastTest {
    private val staticPresets = PalettePreset.entries - PalettePreset.SYSTEM

    private fun contrast(
        a: Color,
        b: Color,
    ): Double {
        val (light, dark) = listOf(a.luminance(), b.luminance()).sortedDescending()
        return (light + 0.05) / (dark + 0.05)
    }

    private fun assertContrast(
        minimum: Double,
        pair: String,
        pick: (ColorScheme) -> Pair<Color, Color>,
    ) {
        for (preset in staticPresets) {
            for (dark in listOf(false, true)) {
                val scheme = checkNotNull(staticColorScheme(preset, dark))
                val (a, b) = pick(scheme)
                val ratio = contrast(a, b)
                assertTrue(
                    "$preset ${if (dark) "dark" else "light"}: $pair is $ratio, below $minimum",
                    ratio >= minimum,
                )
            }
        }
    }

    @Test
    fun bordersStandOutFromPaper() =
        assertContrast(3.0, "border vs paper") { it.outline to it.surface }

    @Test
    fun selectedChipTextIsReadable() =
        assertContrast(4.5, "onInkWash vs inkWash") {
            it.onSecondaryContainer to it.secondaryContainer
        }

    @Test
    fun buttonTextIsReadable() =
        assertContrast(4.5, "onPrimary vs primary") { it.onPrimary to it.primary }

    @Test
    fun inkIsReadableOnPaper() = assertContrast(4.5, "ink vs paper") { it.primary to it.surface }

    @Test
    fun systemPaletteHasNoFixedColours() {
        assertNull(staticColorScheme(PalettePreset.SYSTEM, dark = false))
        assertNull(staticColorScheme(PalettePreset.SYSTEM, dark = true))
    }
}
