package local.writingassistant.core

import local.writingassistant.core.ModelRouting.pickTier
import local.writingassistant.core.ModelTier.LARGE
import local.writingassistant.core.ModelTier.SMALL
import org.junit.Assert.assertEquals
import org.junit.Test

class ModelRoutingTest {
    private fun repeated(
        word: String,
        count: Int,
    ) = List(count) { word }.joinToString(" ")

    @Test
    fun shortEnglishRoutesToHaiku() {
        assertEquals(SMALL, pickTier("Please send me the report by end of day."))
        assertEquals(SMALL, pickTier("Can you review this before our meeting tomorrow?"))
        assertEquals(SMALL, pickTier("Hello how are you today"))
    }

    @Test
    fun shortSpanishAndPortugueseRouteToSonnet() {
        assertEquals(
            LARGE,
            pickTier("Por favor envíame el informe antes de que termine el día."),
        )
        assertEquals(
            LARGE,
            pickTier("Por favor me envie o relatório antes do final do dia."),
        )
        assertEquals(LARGE, pickTier("El proyecto está listo para revisión"))
    }

    @Test
    fun asciiRomanceTextWithTwoStopwordsRoutesToSonnet() {
        assertEquals(LARGE, pickTier("Necesito que me ayudes con esto"))
    }

    @Test
    fun wordCountBoundaryIsSixty() {
        assertEquals(SMALL, pickTier(repeated("word", 60)))
        assertEquals(LARGE, pickTier(repeated("word", 61)))
        assertEquals(LARGE, pickTier(repeated("hello", 70)))
    }

    @Test
    fun wordsAreSplitOnAnyUnicodeWhitespace() {
        val longWords = List(61) { "a".repeat(200) }

        assertEquals(LARGE, pickTier(longWords.joinToString("\u00A0")))
        assertEquals(LARGE, pickTier(longWords.joinToString("\u2003")))
    }

    @Test
    fun shortAsciiUnknownWordRoutesToHaiku() {
        assertEquals(SMALL, pickTier("Hola"))
    }

    @Test
    fun emptyStringRoutesToSonnet() {
        assertEquals(LARGE, pickTier(""))
    }

    @Test
    fun whitespaceOnlyRoutesToHaiku() {
        assertEquals(SMALL, pickTier("   "))
    }

    @Test
    fun accentedCharactersRouteToSonnet() {
        assertEquals(LARGE, pickTier("Désolé, je suis en retard."))
    }

    @Test
    fun oneStopwordHitStillRoutesToHaiku() {
        assertEquals(SMALL, pickTier("Send the report pero today"))
    }

    @Test
    fun stopwordsWithPunctuationAndCapitalsCount() {
        assertEquals(LARGE, pickTier("\"El\" report, PERO! today"))
    }

    @Test
    fun nonAsciiRatioOfExactlyTwoPercentRoutesToHaiku() {
        assertEquals(SMALL, pickTier("é" + "a".repeat(49)))
    }

    @Test
    fun nonAsciiRatioAboveTwoPercentRoutesToSonnet() {
        assertEquals(LARGE, pickTier("é" + "a".repeat(48)))
    }

    @Test
    fun nonAsciiRatioCountsCodePointsNotUtf16Units() {
        assertEquals(SMALL, pickTier("😀" + "a".repeat(49)))
    }
}
