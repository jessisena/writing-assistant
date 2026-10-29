package local.writingassistant.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

class PolishServiceTest {
    private fun service(
        client: LlmClient,
        timeout: Duration = PolishService.DEFAULT_TIMEOUT,
    ) = PolishService(client, StubPromptReader(), timeout)

    private suspend fun polish(
        output: String,
        text: String = "Send me the report pls",
    ): PolishResult = service(replying(output)).polish(text, Channel.SLACK)

    private suspend fun assertBadFormat(output: String) {
        val error = thrownBy { polish(output) }
        assertTrue("$output gave $error", error is PolishError.BadFormat)
    }

    @Test
    fun translatedInputHasNoSummary() =
        runTest {
            listOf("Spanish", "Portuguese", "French").forEach { language ->
                val result = polish(translatedResponse(language), text = "some text")

                assertTrue(result.wasTranslated)
                assertNull(result.learningSummary)
                assertEquals(language, result.detectedLanguage)
            }
        }

    @Test
    fun disobedientModelSummaryIsStripped() =
        runTest {
            val output =
                json(
                    "detected_language" to JsonPrimitive("Spanish"),
                    "was_translated" to JsonPrimitive(true),
                    "polished_text" to JsonPrimitive("Please send me the report by end of day."),
                    "learning_summary" to summaryObject(),
                )

            val result = polish(output, text = "Texto en español")

            assertTrue(result.wasTranslated)
            assertNull(result.learningSummary)
        }

    @Test
    fun englishInputKeepsSummary() =
        runTest {
            val result = polish(englishResponse)

            assertFalse(result.wasTranslated)
            assertEquals("Please send me the report by end of day.", result.polishedText)
            assertEquals("English", result.detectedLanguage)
            val summary = checkNotNull(result.learningSummary)
            assertEquals("send me the report pls", summary.corrections.single().original)
            assertEquals("by end of day", summary.vocabulary.single().term)
            assertTrue(summary.grammarInsight.startsWith("Spelling out"))
        }

    @Test
    fun malformedSummaryOnTranslatedResponseIsIgnored() =
        runTest {
            val output =
                json(
                    "polished_text" to JsonPrimitive("Hi"),
                    "was_translated" to JsonPrimitive(true),
                    "learning_summary" to JsonPrimitive(42),
                )

            assertNull(polish(output).learningSummary)
        }

    @Test
    fun truthyWasTranslatedDropsSummary() =
        runTest {
            listOf(
                JsonPrimitive(true),
                JsonPrimitive(1),
                JsonPrimitive(-0.5),
                JsonPrimitive("false"),
                JsonPrimitive("true"),
                buildJsonArray { add(0) },
                nonEmptyObject,
            ).forEach { value ->
                val result = polish(responseWithSummary(value))

                assertTrue("$value should be truthy", result.wasTranslated)
                assertNull("$value should drop the summary", result.learningSummary)
            }
        }

    @Test
    fun falsyWasTranslatedKeepsSummary() =
        runTest {
            listOf(
                null,
                JsonPrimitive(false),
                JsonPrimitive(0),
                JsonPrimitive(0.0),
                JsonPrimitive(""),
                emptyArray,
                emptyObject,
                JsonNull,
            ).forEach { value ->
                val result = polish(responseWithSummary(value))

                assertFalse("$value should be falsy", result.wasTranslated)
                assertNotNull("$value should keep the summary", result.learningSummary)
            }
        }

    @Test
    fun absentOrNullSummaryIsNull() =
        runTest {
            val absent =
                json(
                    "polished_text" to JsonPrimitive("Hi"),
                    "was_translated" to JsonPrimitive(false),
                )
            val explicitNull =
                json(
                    "polished_text" to JsonPrimitive("Hi"),
                    "was_translated" to JsonPrimitive(false),
                    "learning_summary" to JsonNull,
                )

            assertNull(polish(absent).learningSummary)
            assertNull(polish(explicitNull).learningSummary)
        }

    @Test
    fun learningSummaryMissingAnyFieldIsBadFormat() =
        runTest {
            for (field in listOf("corrections", "grammar_insight", "vocabulary")) {
                val summary = JsonObject(summaryObject() - field)

                assertBadFormat(
                    json("polished_text" to JsonPrimitive("Hi"), "learning_summary" to summary),
                )
            }
        }

    @Test
    fun summaryWithUnknownKeysStillDecodes() =
        runTest {
            val summary = summaryWith("confidence", JsonPrimitive("high"))
            val output = json("polished_text" to JsonPrimitive("Hi"), "learning_summary" to summary)

            assertNotNull(polish(output).learningSummary)
        }

    @Test
    fun fencedResponseWithPreambleParses() =
        runTest {
            val result = polish("Here you go:\n```json\n$englishResponse\n```")

            assertNotNull(result.learningSummary)
        }

    @Test
    fun responseWithPreambleAndTrailerParses() =
        runTest {
            val result = polish("Result:\n\n$englishResponse\nDone.")

            assertEquals("Please send me the report by end of day.", result.polishedText)
        }

    @Test
    fun unparsableResponseIsBadFormat() =
        runTest {
            listOf("this is not json at all", "", "[1, 2, 3]", "{\"a\": }", "\"just text\"", "42")
                .forEach { assertBadFormat(it) }
        }

    @Test
    fun missingOrNonStringPolishedTextIsBadFormat() =
        runTest {
            assertBadFormat(json("detected_language" to JsonPrimitive("English")))
            assertBadFormat(json("polished_text" to JsonPrimitive(5)))
            assertBadFormat(json("polished_text" to JsonNull))
            assertBadFormat(json("polished_text" to emptyObject))
        }

    @Test
    fun malformedLearningSummaryIsBadFormat() =
        runTest {
            val summaries =
                listOf(
                    buildJsonObject { putJsonArray("corrections") {} },
                    JsonPrimitive("not an object"),
                    emptyArray,
                    summaryWith(
                        "corrections",
                        buildJsonArray { add(buildJsonObject { put("original", "x") }) },
                    ),
                    summaryWith("grammar_insight", JsonNull),
                    summaryWith("grammar_insight", JsonPrimitive(5)),
                    summaryWith("vocabulary", JsonPrimitive("none")),
                )

            summaries.forEach { summary ->
                assertBadFormat(
                    json(
                        "polished_text" to JsonPrimitive("Hi"),
                        "learning_summary" to summary,
                    ),
                )
            }
        }

    @Test
    fun detectedLanguageDefaultsToUnknown() =
        runTest {
            assertEquals(
                "Unknown",
                polish(json("polished_text" to JsonPrimitive("Hi"))).detectedLanguage,
            )
            val numeric =
                json(
                    "polished_text" to JsonPrimitive("Hi"),
                    "detected_language" to JsonPrimitive(3),
                )
            assertEquals("Unknown", polish(numeric).detectedLanguage)
        }

    @Test
    fun clientErrorPropagatesUnchanged() =
        runTest {
            val error = PolishError.Timeout(120)
            val service = service(FakeLlmClient(listOf(Result.failure(error))))

            assertSame(error, thrownBy { service.polish("Hello", Channel.SLACK) })
        }

    @Test
    fun unreadablePromptIsPromptUnavailableAndSkipsTheCall() =
        runTest {
            listOf(PromptFile.Global, PromptFile.ForChannel(Channel.SLACK)).forEach { file ->
                val client = replying(englishResponse)
                val service = PolishService(client, StubPromptReader(missing = setOf(file)))

                val error = thrownBy { service.polish("Hello", Channel.SLACK) }

                assertEquals(
                    PolishError.PromptUnavailable("${file.relativePath} is missing"),
                    error,
                )
                assertTrue(client.calls.isEmpty())
            }
        }

    @Test
    fun checkReadyForwardsClientAvailability() =
        runTest {
            val client = FakeLlmClient()
            val service = service(client)
            service.checkReady()

            client.availabilityError = PolishError.InvalidApiKey

            assertSame(PolishError.InvalidApiKey, thrownBy { service.checkReady() })
        }

    @Test
    fun emptyOrWhitespaceInputIsRejectedWithoutACall() =
        runTest {
            listOf("", "   ", " \n\t ").forEach { text ->
                val client = replying(englishResponse)

                val error =
                    thrownBy { service(client).polish(text, Channel.SLACK) }

                assertEquals(PolishError.EmptyInput, error)
                assertTrue(client.calls.isEmpty())
            }
        }

    @Test
    fun inputWithinLimitIsAccepted() =
        runTest {
            val texts =
                listOf(
                    "a",
                    "a".repeat(PolishService.MAX_INPUT_LENGTH),
                    "😀".repeat(PolishService.MAX_INPUT_LENGTH),
                    "  " + "a".repeat(PolishService.MAX_INPUT_LENGTH) + "\n",
                )
            texts.forEach { text ->
                val client = replying(englishResponse)

                service(client).polish(text, Channel.SLACK)

                assertEquals(1, client.calls.size)
            }
        }

    @Test
    fun inputOverLimitIsRejectedWithoutACall() =
        runTest {
            val texts =
                listOf(
                    "a".repeat(PolishService.MAX_INPUT_LENGTH + 1),
                    "é".repeat(PolishService.MAX_INPUT_LENGTH / 2 + 1),
                )
            texts.forEach { text ->
                val client = replying(englishResponse)

                val error =
                    thrownBy { service(client).polish(text, Channel.SLACK) }

                assertEquals(PolishError.InputTooLong(20_000), error)
                assertTrue(client.calls.isEmpty())
            }
        }

    @Test
    fun clientReceivesPromptModelAndTimeout() =
        runTest {
            val client = replying(englishResponse)

            val result =
                service(client, 7.seconds).polish("  Hello there \n", Channel.FORMAL)

            assertEquals(
                listOf(
                    FakeLlmClient.Call(
                        "SYSTEM FORMAL RULES\n\n---\n\nHello there",
                        Provider.ANTHROPIC.models.small,
                        7.seconds,
                    ),
                ),
                client.calls,
            )
            assertEquals(Provider.ANTHROPIC.models.small, result.modelUsed)
        }

    @Test
    fun defaultTimeoutIsTwoMinutes() =
        runTest {
            val client = replying(englishResponse)

            service(client).polish("Hello", Channel.SLACK)

            assertEquals(120.seconds, client.calls.single().timeout)
        }

    @Test
    fun nonEnglishInputUsesSonnet() =
        runTest {
            val client = replying(translatedResponse("Spanish"))
            val text = "Por favor envíame el informe antes de que termine el día."

            val result = service(client).polish(text, Channel.SLACK)

            assertEquals(Provider.ANTHROPIC.models.large, client.calls.single().model)
            assertEquals(Provider.ANTHROPIC.models.large, result.modelUsed)
        }

    @Test
    fun backendModelsArePickedPerTierAndReported() =
        runTest {
            val client = replying(englishResponse, translatedResponse("Spanish"))
            val service =
                PolishService({ Backend(client, Models("s", "l")) }, StubPromptReader())

            val english = service.polish("Hello there", Channel.SLACK)
            val spanish = service.polish("Por favor envíame el informe hoy.", Channel.SLACK)

            assertEquals(listOf("s", "l"), client.calls.map { it.model })
            assertEquals("s", english.modelUsed)
            assertEquals("l", spanish.modelUsed)
        }

    @Test
    fun backendIsResolvedOnEveryCall() =
        runTest {
            val first = replying(englishResponse)
            val second = replying(englishResponse, englishResponse)
            var current = Backend(first, Models("first-s", "first-l"))
            val service = PolishService({ current }, StubPromptReader())

            service.polish("Hello", Channel.SLACK)
            current = Backend(second, Models("second-s", "second-l"))
            val result = service.polish("Hello", Channel.SLACK)
            service.refine("Hello", Channel.SLACK, Refinement.SHORTER)

            assertEquals(listOf("first-s"), first.calls.map { it.model })
            assertEquals(listOf("second-s", "second-s"), second.calls.map { it.model })
            assertEquals("second-s", result.modelUsed)
        }

    @Test
    fun checkReadyUsesTheCurrentBackendsClient() =
        runTest {
            val healthy = FakeLlmClient()
            val rejected = FakeLlmClient().apply { availabilityError = PolishError.InvalidApiKey }
            var current = Backend(rejected, Models("s", "l"))
            val service = PolishService({ current }, StubPromptReader())

            assertSame(PolishError.InvalidApiKey, thrownBy { service.checkReady() })
            current = Backend(healthy, Models("s", "l"))
            service.checkReady()
        }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun cancellationPropagatesWhileWaitingForTheModel() =
        runTest {
            val service = service(HangingClient())
            val pending = async { service.polish("Hello", Channel.SLACK) }
            runCurrent()

            pending.cancel()

            assertTrue(thrownBy { pending.await() } is CancellationException)
        }

    @Test
    fun cancellationFromTheClientIsNotWrapped() =
        runTest {
            val cancellation = CancellationException("stopped")
            val service = service(FakeLlmClient(listOf(Result.failure(cancellation))))

            assertSame(cancellation, thrownBy { service.polish("Hello", Channel.SLACK) })
        }

    private class HangingClient : LlmClient {
        override suspend fun run(
            prompt: String,
            model: String,
            timeout: Duration,
        ): String = awaitCancellation()

        override suspend fun checkAvailable() = Unit
    }
}
