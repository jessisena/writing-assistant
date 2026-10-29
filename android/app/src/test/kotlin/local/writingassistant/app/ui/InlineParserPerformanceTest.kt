package local.writingassistant.app.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.time.measureTimedValue

class InlineParserPerformanceTest {
    private fun parseWithin1s(line: String): List<InlineSpan> {
        val (spans, duration) = measureTimedValue { InlineParser.parse(line) }
        println("parsed ${line.length} chars in $duration")
        assertTrue("took $duration", duration.inWholeMilliseconds < MAX_MILLIS)
        return spans
    }

    private fun assertParsesLiterallyWithin1s(line: String) {
        assertEquals(listOf(InlineSpan(line, InlineStyle())), parseWithin1s(line))
    }

    @Test
    fun `many opener-only asterisks parse quickly`() {
        assertParsesLiterallyWithin1s(" *a".repeat(200))
    }

    @Test
    fun `a realistic line of unclosed asterisks parses quickly`() {
        assertParsesLiterallyWithin1s(
            "Notes: *see appendix, *draft, *pending review, *v2, *todo ".repeat(6),
        )
    }

    @Test
    fun `many unclosed backticks and brackets parse quickly`() {
        parseWithin1s(" *a ` [b ".repeat(300))
    }

    private companion object {
        const val MAX_MILLIS = 1000
    }
}
