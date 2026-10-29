package local.writingassistant.core

import kotlinx.coroutines.test.runTest
import local.writingassistant.core.api.AnthropicClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.time.Duration.Companion.minutes

/** Sends real text through the Anthropic API. Run with `./gradlew :core:liveTest`. */
class LivePolishTest {
    private val service =
        PolishService(
            client = AnthropicClient(apiKey = { System.getenv("ANTHROPIC_API_KEY") }),
            prompts = DirectoryPromptReader(File(System.getProperty("prompts.dir"))),
        )

    @Test
    fun shortEnglishTextIsPolishedByHaiku() =
        runTest(timeout = 3.minutes) {
            val result =
                service.polish("hey can u check the PR before tomorow? thx", Channel.SLACK)

            assertEquals(Provider.ANTHROPIC.models.small, result.modelUsed)
            assertTrue(result.polishedText.isNotBlank())
            assertTrue(result.polishedText.contains("tomorrow", ignoreCase = true))
        }

    @Test
    fun spanishTextIsTranslatedBySonnetWithoutASummary() =
        runTest(timeout = 3.minutes) {
            val result =
                service.polish(
                    "Hola equipo, mañana no podré estar en la reunión porque tengo médico.",
                    Channel.SLACK,
                )

            assertEquals(Provider.ANTHROPIC.models.large, result.modelUsed)
            assertTrue(result.wasTranslated)
            assertNull(result.learningSummary)
            assertTrue(result.polishedText.isNotBlank())
        }

    @Test
    fun refineReturnsShorterText() =
        runTest(timeout = 3.minutes) {
            val text =
                "Hi team, I wanted to let you know that I will be a little late to the " +
                    "standup meeting tomorrow morning because I have a dentist appointment."

            val refined = service.refine(text, Channel.SLACK, Refinement.SHORTER)

            assertTrue(refined.isNotBlank())
            assertTrue(refined.length < text.length)
        }
}
