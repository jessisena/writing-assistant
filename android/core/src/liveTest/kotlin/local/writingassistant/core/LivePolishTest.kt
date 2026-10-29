package local.writingassistant.core

import kotlinx.coroutines.test.runTest
import local.writingassistant.core.api.AnthropicClient
import local.writingassistant.core.api.GroqClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import kotlin.time.Duration.Companion.minutes

/**
 * Sends real text through each provider whose key is set (`ANTHROPIC_API_KEY`,
 * `GROQ_API_KEY`); the other provider's cases are skipped. Run with `./gradlew :core:liveTest`.
 */
class LivePolishTest {
    private val prompts = DirectoryPromptReader(File(System.getProperty("prompts.dir")))

    private fun serviceFor(provider: Provider): PolishService {
        val variable = "${provider.id.uppercase()}_API_KEY"
        val key = System.getenv(variable)
        assumeTrue("$variable is not set", !key.isNullOrBlank())
        val client =
            when (provider) {
                Provider.ANTHROPIC -> AnthropicClient(apiKey = { key })
                Provider.GROQ -> GroqClient(apiKey = { key })
            }
        return PolishService({ Backend(client, provider.models) }, prompts)
    }

    private suspend fun assertShortEnglishUsesSmallModel(provider: Provider) {
        val result =
            serviceFor(provider).polish("hey can u check the PR before tomorow? thx", Channel.SLACK)

        assertEquals(provider.models.small, result.modelUsed)
        assertTrue(result.polishedText.isNotBlank())
        assertTrue(result.polishedText.contains("tomorrow", ignoreCase = true))
    }

    private suspend fun assertTranslatedByLargeModel(
        provider: Provider,
        text: String,
    ) {
        val result = serviceFor(provider).polish(text, Channel.SLACK)

        assertEquals(provider.models.large, result.modelUsed)
        assertTrue(result.wasTranslated)
        assertNull(result.learningSummary)
        assertTrue(result.polishedText.isNotBlank())
    }

    private suspend fun assertRefineShortens(provider: Provider) {
        val refined = serviceFor(provider).refine(LONG_ENGLISH, Channel.SLACK, Refinement.SHORTER)

        assertTrue(refined.isNotBlank())
        assertTrue(refined.length < LONG_ENGLISH.length)
    }

    @Test
    fun anthropicShortEnglishTextIsPolishedByTheSmallModel() =
        runTest(timeout = 3.minutes) { assertShortEnglishUsesSmallModel(Provider.ANTHROPIC) }

    @Test
    fun anthropicSpanishTextIsTranslatedWithoutASummary() =
        runTest(timeout = 3.minutes) { assertTranslatedByLargeModel(Provider.ANTHROPIC, SPANISH) }

    @Test
    fun anthropicRefineReturnsShorterText() =
        runTest(timeout = 3.minutes) { assertRefineShortens(Provider.ANTHROPIC) }

    @Test
    fun groqShortEnglishTextIsPolishedByTheSmallModel() =
        runTest(timeout = 3.minutes) { assertShortEnglishUsesSmallModel(Provider.GROQ) }

    @Test
    fun groqSpanishTextIsTranslatedWithoutASummary() =
        runTest(timeout = 3.minutes) { assertTranslatedByLargeModel(Provider.GROQ, SPANISH) }

    @Test
    fun groqCatalanTextIsTranslatedWithoutASummary() =
        runTest(timeout = 3.minutes) { assertTranslatedByLargeModel(Provider.GROQ, CATALAN) }

    @Test
    fun groqRefineReturnsShorterText() =
        runTest(timeout = 3.minutes) { assertRefineShortens(Provider.GROQ) }

    private companion object {
        const val SPANISH =
            "Hola equipo, mañana no podré estar en la reunión porque tengo médico."
        const val CATALAN =
            "Bon dia a tothom, demà no podré venir a la reunió perquè estic malalt."
        const val LONG_ENGLISH =
            "Hi team, I wanted to let you know that I will be a little late to the " +
                "standup meeting tomorrow morning because I have a dentist appointment."
    }
}
