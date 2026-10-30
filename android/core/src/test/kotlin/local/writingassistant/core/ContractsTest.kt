package local.writingassistant.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ContractsTest {
    @Test
    fun everyPromptFileExistsInTheSharedPromptsDirectory() {
        val dir = File(System.getProperty("prompts.dir"))
        val missing = PromptFile.all.filterNot { File(dir, it.relativePath).isFile }

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
                PolishError.HistoryFailed("detail"),
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
    fun promptFilesListTopLevelFilesThenChannelsThenRefinements() {
        val expected =
            listOf(
                PromptFile.Global,
                PromptFile.Always,
                PromptFile.LearningSummary,
                PromptFile.Refine,
            ) +
                Channel.entries.map { PromptFile.ForChannel(it) } +
                Refinement.entries.map { PromptFile.ForRefinement(it) } +
                listOf(
                    PromptFile.ForMode(Mode.WORK),
                    PromptFile.ForMode(Mode.PERSONAL),
                    PromptFile.ForLanguage(OutputLanguage.ENGLISH),
                    PromptFile.ForLanguage(OutputLanguage.SAME_AS_INPUT),
                )

        assertEquals(expected, PromptFile.all)
        assertEquals(
            listOf(
                "modes/work.txt",
                "modes/personal.txt",
                "languages/english.txt",
                "languages/same_as_input.txt",
            ),
            PromptFile.all.takeLast(4).map { it.relativePath },
        )
        PromptFile.all.forEach { assertEquals(it, PromptFile.fromRelativePath(it.relativePath)) }
        assertEquals(null, PromptFile.fromRelativePath("channels/nope.txt"))
    }

    @Test
    fun idsMatchTheMacApp() {
        assertEquals(
            listOf(
                "slack",
                "slack_informal",
                "talking_points",
                "formal",
                "ai_prompt",
                "email",
                "personal_message",
                "proofread",
                "other",
            ),
            Channel.entries.map { it.id },
        )
        assertEquals(
            listOf("shorter", "more_casual", "more_formal", "more_diplomatic", "more_assertive"),
            Refinement.entries.map { it.id },
        )
        assertEquals(listOf("work", "personal"), Mode.entries.map { it.id })
        assertEquals(listOf("english", "sameAsInput"), OutputLanguage.entries.map { it.id })
        assertEquals(Mode.PERSONAL, Mode.WORK.toggled)
        assertEquals(Mode.WORK, Mode.PERSONAL.toggled)
    }

    @Test
    fun channelFromIdRoundTripsAndRejectsUnknownIds() {
        Channel.entries.forEach { assertEquals(it, Channel.fromId(it.id)) }
        assertEquals(null, Channel.fromId("nope"))
    }
}
