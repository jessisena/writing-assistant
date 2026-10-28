package local.writingassistant.core

import local.writingassistant.core.ModelRouting.HAIKU_MODEL
import local.writingassistant.core.ModelRouting.SONNET_MODEL
import local.writingassistant.core.ModelRouting.pickModel
import org.junit.Assert.assertEquals
import org.junit.Test

class ModelRoutingTest {
    private fun repeated(
        word: String,
        count: Int,
    ) = List(count) { word }.joinToString(" ")

    @Test
    fun shortEnglishRoutesToHaiku() {
        assertEquals(HAIKU_MODEL, pickModel("Please send me the report by end of day."))
        assertEquals(HAIKU_MODEL, pickModel("Can you review this before our meeting tomorrow?"))
        assertEquals(HAIKU_MODEL, pickModel("Hello how are you today"))
    }

    @Test
    fun shortSpanishAndPortugueseRouteToSonnet() {
        assertEquals(
            SONNET_MODEL,
            pickModel("Por favor envíame el informe antes de que termine el día."),
        )
        assertEquals(
            SONNET_MODEL,
            pickModel("Por favor me envie o relatório antes do final do dia."),
        )
        assertEquals(SONNET_MODEL, pickModel("El proyecto está listo para revisión"))
    }

    @Test
    fun asciiRomanceTextWithTwoStopwordsRoutesToSonnet() {
        assertEquals(SONNET_MODEL, pickModel("Necesito que me ayudes con esto"))
    }

    @Test
    fun wordCountBoundaryIsSixty() {
        assertEquals(HAIKU_MODEL, pickModel(repeated("word", 60)))
        assertEquals(SONNET_MODEL, pickModel(repeated("word", 61)))
        assertEquals(SONNET_MODEL, pickModel(repeated("hello", 70)))
    }

    @Test
    fun wordsAreSplitOnAnyUnicodeWhitespace() {
        val longWords = List(61) { "a".repeat(200) }

        assertEquals(SONNET_MODEL, pickModel(longWords.joinToString("\u00A0")))
        assertEquals(SONNET_MODEL, pickModel(longWords.joinToString("\u2003")))
    }

    @Test
    fun shortAsciiUnknownWordRoutesToHaiku() {
        assertEquals(HAIKU_MODEL, pickModel("Hola"))
    }

    @Test
    fun emptyStringRoutesToSonnet() {
        assertEquals(SONNET_MODEL, pickModel(""))
    }

    @Test
    fun whitespaceOnlyRoutesToHaiku() {
        assertEquals(HAIKU_MODEL, pickModel("   "))
    }

    @Test
    fun accentedCharactersRouteToSonnet() {
        assertEquals(SONNET_MODEL, pickModel("Désolé, je suis en retard."))
    }

    @Test
    fun oneStopwordHitStillRoutesToHaiku() {
        assertEquals(HAIKU_MODEL, pickModel("Send the report pero today"))
    }

    @Test
    fun stopwordsWithPunctuationAndCapitalsCount() {
        assertEquals(SONNET_MODEL, pickModel("\"El\" report, PERO! today"))
    }

    @Test
    fun nonAsciiRatioOfExactlyTwoPercentRoutesToHaiku() {
        assertEquals(HAIKU_MODEL, pickModel("é" + "a".repeat(49)))
    }

    @Test
    fun nonAsciiRatioAboveTwoPercentRoutesToSonnet() {
        assertEquals(SONNET_MODEL, pickModel("é" + "a".repeat(48)))
    }

    @Test
    fun nonAsciiRatioCountsCodePointsNotUtf16Units() {
        assertEquals(HAIKU_MODEL, pickModel("😀" + "a".repeat(49)))
    }
}
