package local.writingassistant.core

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import java.io.IOException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Runs the polish pipeline: validate input, assemble the prompt, call Claude, parse the reply.
 * Mirrors `PolishService.swift`.
 *
 * @param client Sends prompts to Claude. Its [PolishError]s propagate unchanged.
 * @param prompts Supplies the prompt files.
 * @param timeout Upper bound for a single Claude call.
 */
class PolishService(
    private val client: ClaudeClient,
    private val prompts: PromptReading,
    private val timeout: Duration = DEFAULT_TIMEOUT,
) : Polishing {
    private val assembler = PromptAssembler(prompts)

    /**
     * Polishes (or translates, then polishes) [text] for [channel].
     *
     * When the model reports a truthy `was_translated`, the result never carries a learning
     * summary, whatever the model returned.
     *
     * @throws PolishError EmptyInput, InputTooLong, PromptUnavailable, BadFormat, or any error
     *   thrown by the client, unchanged.
     */
    override suspend fun polish(
        text: String,
        channel: Channel,
    ): PolishResult {
        val input = validatedInput(text)
        val systemPrompt = loadPrompt { assembler.assemble(channel) }
        val model = ModelRouting.pickModel(input)
        return parse(send(systemPrompt, input, model), model)
    }

    /**
     * Rewrites already-polished [text] for [channel], following one [refinement] instruction.
     *
     * Only `polished_text` is read from the reply: the model's language and learning summary
     * describe its own output, so they are ignored, even when malformed.
     *
     * @throws PolishError EmptyInput, InputTooLong, PromptUnavailable, BadFormat, or any error
     *   thrown by the client, unchanged.
     */
    override suspend fun refine(
        text: String,
        channel: Channel,
        refinement: Refinement,
    ): String {
        val input = validatedInput(text)
        val systemPrompt = loadPrompt { assembler.assemble(channel) }
        val instruction = loadPrompt { prompts.read(PromptFile.ForRefinement(refinement)).trim() }
        val refinementPrompt =
            "$systemPrompt\n\n## Additional instruction\n\n$instruction\n\n$REFINEMENT_NOTE"
        val raw = send(refinementPrompt, input, ModelRouting.pickModel(input))
        return polishedText(decodeObject(raw))
    }

    override suspend fun checkReady() {
        client.checkAvailable()
    }

    private suspend fun send(
        systemPrompt: String,
        input: String,
        model: String,
    ): String = client.run("$systemPrompt\n\n---\n\n$input", model, timeout)

    companion object {
        const val MAX_INPUT_LENGTH = 20_000
        val DEFAULT_TIMEOUT: Duration = 120.seconds

        private const val REFINEMENT_NOTE =
            "The input is already-polished English: apply the additional instruction on top of " +
                "the rules above, set was_translated to false and set learning_summary to null."
        private val SUMMARY_KEYS = listOf("corrections", "grammar_insight", "vocabulary")
        private val json = Json { ignoreUnknownKeys = true }

        private fun validatedInput(text: String): String {
            val trimmed = text.trim()
            if (trimmed.isEmpty()) {
                throw PolishError.EmptyInput
            }
            if (trimmed.codePointCount(0, trimmed.length) > MAX_INPUT_LENGTH) {
                throw PolishError.InputTooLong(MAX_INPUT_LENGTH)
            }
            return trimmed
        }

        private fun loadPrompt(body: () -> String): String =
            try {
                body()
            } catch (e: IOException) {
                throw PolishError.PromptUnavailable(e.message ?: e.toString())
            }

        private fun parse(
            raw: String,
            model: String,
        ): PolishResult {
            val response = decodeObject(raw)
            val polishedText = polishedText(response)
            val wasTranslated = isTruthy(response["was_translated"])
            val summary = if (wasTranslated) null else decodeSummary(response["learning_summary"])
            return PolishResult(
                polishedText = polishedText,
                learningSummary = summary,
                detectedLanguage = stringValue(response["detected_language"]) ?: "Unknown",
                wasTranslated = wasTranslated,
                modelUsed = model,
            )
        }

        private fun polishedText(response: JsonObject): String =
            stringValue(response["polished_text"])
                ?: throw PolishError.BadFormat("missing or non-string polished_text")

        private fun stringValue(element: JsonElement?): String? =
            (element as? JsonPrimitive)?.takeIf { it.isString }?.content

        private fun decodeObject(raw: String): JsonObject {
            val element =
                try {
                    json.parseToJsonElement(JsonExtraction.extractJsonText(raw))
                } catch (e: SerializationException) {
                    throw PolishError.BadFormat("response is not valid JSON: ${e.message}")
                }
            return element as? JsonObject
                ?: throw PolishError.BadFormat("response JSON is not an object")
        }

        private fun decodeSummary(element: JsonElement?): LearningSummary? {
            if (element == null || element is JsonNull) {
                return null
            }
            if (element !is JsonObject) {
                throw PolishError.BadFormat("learning_summary is not an object")
            }
            val missing = SUMMARY_KEYS.filterNot { it in element }
            if (missing.isNotEmpty()) {
                throw PolishError.BadFormat("invalid learning_summary: missing $missing")
            }
            return try {
                json.decodeFromJsonElement(LearningSummary.serializer(), element)
            } catch (e: SerializationException) {
                throw PolishError.BadFormat("invalid learning_summary: ${e.message}")
            }
        }

        /** Mirrors Python's `bool()` so any truthy `was_translated` drops the summary. */
        private fun isTruthy(element: JsonElement?): Boolean =
            when (element) {
                null, JsonNull -> false
                is JsonObject -> element.isNotEmpty()
                is JsonArray -> element.isNotEmpty()
                is JsonPrimitive -> isTruthyPrimitive(element)
            }

        private fun isTruthyPrimitive(primitive: JsonPrimitive): Boolean =
            if (primitive.isString) {
                primitive.content.isNotEmpty()
            } else {
                primitive.booleanOrNull ?: ((primitive.doubleOrNull ?: 0.0) != 0.0)
            }
    }
}
