package local.writingassistant.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.time.Duration.Companion.seconds

class RefineTest {
    private val refinedResponse =
        json(
            "detected_language" to JsonPrimitive("English"),
            "was_translated" to JsonPrimitive(false),
            "polished_text" to JsonPrimitive("Send the report today."),
            "learning_summary" to summaryObject(),
        )

    private fun service(
        client: ClaudeClient,
        prompts: PromptReading = StubPromptReader(),
    ) = PolishService(client, prompts, 9.seconds)

    private suspend fun PolishService.refineHello() =
        refine("Hello", Channel.SLACK, Refinement.SHORTER)

    @Test
    fun promptAppendsTheRefinementInstructionBeforeTheInput() =
        runTest {
            Refinement.entries.forEach { refinement ->
                val client = replying(refinedResponse)

                service(client).refine("  Please send me the report.\n", Channel.FORMAL, refinement)

                val instruction = "${refinement.id.uppercase()} INSTRUCTION"
                val expected =
                    "SYSTEM FORMAL RULES\n\n## Additional instruction\n\n$instruction\n\n" +
                        "The input is already-polished English: apply the additional instruction " +
                        "on top of the rules above, set was_translated to false and set " +
                        "learning_summary to null.\n\n---\n\nPlease send me the report."
                assertEquals(expected, client.calls.single().prompt)
            }
        }

    @Test
    fun returnsOnlyThePolishedText() =
        runTest {
            val refined =
                service(replying(refinedResponse))
                    .refine("Please send me the report.", Channel.SLACK, Refinement.SHORTER)

            assertEquals("Send the report today.", refined)
        }

    @Test
    fun clientReceivesRoutedModelAndTimeout() =
        runTest {
            val client = replying(refinedResponse, refinedResponse)
            val service = service(client)

            service.refine("Hi", Channel.SLACK, Refinement.SHORTER)
            service.refine("word ".repeat(100), Channel.SLACK, Refinement.SHORTER)

            assertEquals(
                listOf(ModelRouting.HAIKU_MODEL, ModelRouting.SONNET_MODEL),
                client.calls.map { it.model },
            )
            assertTrue(client.calls.all { it.timeout == 9.seconds })
        }

    @Test
    fun emptyInputIsRejectedWithoutACall() =
        runTest {
            listOf("", " \n\t ").forEach { text ->
                val client = replying(refinedResponse)

                val error =
                    thrownBy { service(client).refine(text, Channel.SLACK, Refinement.SHORTER) }

                assertEquals(PolishError.EmptyInput, error)
                assertTrue(client.calls.isEmpty())
            }
        }

    @Test
    fun inputOverLimitIsRejectedWithoutACall() =
        runTest {
            val client = replying(refinedResponse)
            val text = "a".repeat(PolishService.MAX_INPUT_LENGTH + 1)

            val error =
                thrownBy { service(client).refine(text, Channel.SLACK, Refinement.MORE_FORMAL) }

            assertEquals(PolishError.InputTooLong(PolishService.MAX_INPUT_LENGTH), error)
            assertTrue(client.calls.isEmpty())
        }

    @Test
    fun unreadablePromptIsPromptUnavailableAndSkipsTheCall() =
        runTest {
            val files =
                listOf(
                    PromptFile.ForRefinement(Refinement.SHORTER),
                    PromptFile.ForChannel(Channel.SLACK),
                    PromptFile.Global,
                )
            files.forEach { file ->
                val client = replying(refinedResponse)
                val prompts = StubPromptReader(missing = setOf(file))

                val error =
                    thrownBy { service(client, prompts).refineHello() }

                assertEquals(
                    PolishError.PromptUnavailable("${file.relativePath} is missing"),
                    error,
                )
                assertTrue(client.calls.isEmpty())
            }
        }

    @Test
    fun unusableResponseIsBadFormat() =
        runTest {
            val outputs =
                listOf(
                    "not json",
                    "[1]",
                    json("was_translated" to JsonPrimitive(false)),
                    json("polished_text" to JsonPrimitive(3)),
                )
            outputs.forEach { output ->
                val error =
                    thrownBy { service(replying(output)).refineHello() }

                assertTrue("$output gave $error", error is PolishError.BadFormat)
            }
        }

    @Test
    fun clientErrorPropagatesUnchanged() =
        runTest {
            val failure = PolishError.ApiFailed(500, "boom")
            val client = FakeClaudeClient(listOf(Result.failure(failure)))

            assertSame(failure, thrownBy { service(client).refineHello() })
        }

    @Test
    fun learningSummaryAndOtherFieldsAreIgnored() =
        runTest {
            val text = "polished_text" to JsonPrimitive("Hey there")
            val outputs =
                listOf(
                    json(text, "learning_summary" to emptyObject),
                    json(text, "learning_summary" to JsonPrimitive(42)),
                    json(text, "learning_summary" to JsonPrimitive("notes")),
                    json(text, "was_translated" to JsonPrimitive("yes")),
                    json(text, "detected_language" to JsonPrimitive(7)),
                    json(text),
                )
            outputs.forEach { output ->
                assertEquals(output, "Hey there", service(replying(output)).refineHello())
            }
        }

    @Test
    fun bundledPromptsBuildTheRefinementPrompt() =
        runTest {
            val bundled = DirectoryPromptReader(File(System.getProperty("prompts.dir")))
            val client = replying(json("polished_text" to JsonPrimitive("Hi")))

            service(client, bundled).refine("Hello there", Channel.SLACK, Refinement.SHORTER)

            val prompt = client.calls.single().prompt
            val instruction = bundled.read(PromptFile.ForRefinement(Refinement.SHORTER)).trim()
            val guidelines = bundled.read(PromptFile.ForChannel(Channel.SLACK)).trim()
            assertTrue(prompt.contains("## Additional instruction\n\n$instruction\n\n"))
            assertTrue(prompt.contains(guidelines))
            assertTrue(prompt.endsWith("\n\n---\n\nHello there"))
        }
}
