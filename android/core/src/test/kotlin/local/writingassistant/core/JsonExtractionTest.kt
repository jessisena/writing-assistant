package local.writingassistant.core

import local.writingassistant.core.JsonExtraction.extractJsonText
import org.junit.Assert.assertEquals
import org.junit.Test

class JsonExtractionTest {
    @Test
    fun fencedJson() {
        assertEquals("{\"key\": \"value\"}", extractJsonText("```json\n{\"key\": \"value\"}\n```"))
    }

    @Test
    fun fenceWithoutLanguageTag() {
        assertEquals("{\"a\": 1}", extractJsonText("```\n{\"a\": 1}\n```"))
    }

    @Test
    fun fenceAfterPreambleWins() {
        assertEquals(
            "{\"a\": 1}",
            extractJsonText("Here you go:\n```json\n{\"a\": 1}\n```\nDone {x}"),
        )
    }

    @Test
    fun firstFenceWins() {
        val raw = "```json\n{\"a\": 1}\n```\nand\n```json\n{\"b\": 2}\n```"
        assertEquals("{\"a\": 1}", extractJsonText(raw))
    }

    @Test
    fun plainJson() {
        assertEquals("{\"key\": \"value\"}", extractJsonText("  {\"key\": \"value\"}\n"))
    }

    @Test
    fun preambleBeforeJson() {
        val raw = "Now I will compile the result:\n\n{\"key\": \"value\"}"
        assertEquals("{\"key\": \"value\"}", extractJsonText(raw))
    }

    @Test
    fun sliceRunsFromFirstOpeningToLastClosingBrace() {
        assertEquals("{\"a\": {\"b\": 1}}", extractJsonText("x {\"a\": {\"b\": 1}} y"))
    }

    @Test
    fun garbageIsReturnedTrimmed() {
        assertEquals("not json at all", extractJsonText(" not json at all \n"))
    }

    @Test
    fun closingBraceBeforeOpeningIsNotSliced() {
        assertEquals("} oops {", extractJsonText("} oops {"))
    }

    @Test
    fun emptyInputStaysEmpty() {
        assertEquals("", extractJsonText(" \n "))
    }
}
