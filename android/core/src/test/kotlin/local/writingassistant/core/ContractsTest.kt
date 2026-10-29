package local.writingassistant.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ContractsTest {
    @Test
    fun everyPromptFileExistsInTheSharedPromptsDirectory() {
        val dir = File(System.getProperty("prompts.dir"))
        val files =
            listOf(PromptFile.Global) +
                Channel.entries.map { PromptFile.ForChannel(it) } +
                Refinement.entries.map { PromptFile.ForRefinement(it) }

        val missing = files.filterNot { File(dir, it.relativePath).isFile }

        assertEquals(emptyList<PromptFile>(), missing)
    }

    @Test
    fun errorMessagesNameNoProviderExceptNoCredits() {
        val errors =
            listOf(
                PolishError.EmptyInput,
                PolishError.InputTooLong(20_000),
                PolishError.MissingApiKey,
                PolishError.InvalidApiKey,
                PolishError.MalformedApiKey,
                PolishError.KeyStorageFailed("detail"),
                PolishError.Overloaded,
                PolishError.TooLongForProvider,
                PolishError.Timeout(120),
                PolishError.Network("detail"),
                PolishError.ApiFailed(500, "detail"),
                PolishError.OutputTooLong,
                PolishError.Refused,
                PolishError.BadFormat("detail"),
                PolishError.PromptUnavailable("detail"),
                PolishError.Unexpected("detail"),
            )
        val providerNames = Provider.entries.map { it.displayName } + "Claude"

        val naming = errors.filter { error -> providerNames.any { error.message.contains(it) } }

        assertEquals(emptyList<PolishError>(), naming)
        assertTrue(PolishError.NoCredits.message.contains("Anthropic"))
    }

    @Test
    fun errorMessagesCarryTheirNumbers() {
        assertEquals(
            "The AI service took longer than 120 seconds. Please try again.",
            PolishError.Timeout(120).message,
        )
        assertEquals(
            "The AI service returned an error (HTTP 502). Please try again.",
            PolishError.ApiFailed(502, "detail").message,
        )
    }

    @Test
    fun providerFromIdRoundTripsAndRejectsUnknownIds() {
        Provider.entries.forEach { assertEquals(it, Provider.fromId(it.id)) }
        assertEquals(null, Provider.fromId("nope"))
    }

    @Test
    fun channelFromIdRoundTripsAndRejectsUnknownIds() {
        Channel.entries.forEach { assertEquals(it, Channel.fromId(it.id)) }
        assertEquals(null, Channel.fromId("nope"))
    }
}
