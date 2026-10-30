package local.writingassistant.core

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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
 * Runs the polish pipeline: validate input, assemble the prompt, call the model, parse the reply.
 * Mirrors `PolishService.swift`.
 *
 * @param backend Returns the client and models to use, resolved once per call so a provider
 *   change in Settings applies to the next request. The client's [PolishError]s propagate
 *   unchanged.
 * @param prompts Supplies the prompt files.
 * @param timeout Upper bound for a single model call.
 * @param io Where prompt files are read, so callers on the main thread don't touch the disk.
 */
class PolishService(
    private val backend: suspend () -> Backend,
    prompts: PromptReading,
    private val timeout: Duration = DEFAULT_TIMEOUT,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : Polishing {
    /** Always uses [client] with Anthropic's models. */
    constructor(
        client: LlmClient,
        prompts: PromptReading,
        timeout: Duration = DEFAULT_TIMEOUT,
    ) : this({ Backend(client, Provider.ANTHROPIC.models) }, prompts, timeout)

    private val assembler = PromptAssembler(prompts)

    private suspend fun loadPrompt(body: () -> String): String =
        try {
            withContext(io) { body() }
        } catch (e: IOException) {
            throw PolishError.PromptUnavailable(e.message ?: e.toString())
        }

    /**
     * Polishes (or translates, then polishes) [text] for [channel].
     *
     * When the model reports a truthy `was_translated`, or [learningSummary] is false, the
     * result never carries a learning summary, whatever the model returned.
     *
     * @param learningSummary False leaves the learning summary section out of the prompt.
     *
     * @throws PolishError EmptyInput, InputTooLong, PromptUnavailable, BadFormat, or any error
     *   thrown by the client, unchanged.
     */
    override suspend fun polish(
        text: String,
        channel: Channel,
        learningSummary: Boolean,
    ): PolishResult {
        val input = validatedInput(text)
        val systemPrompt = loadPrompt { assembler.assemble(channel, learningSummary) }
        val backend = backend()
        val model = backend.models.forTier(ModelRouting.pickTier(input))
        return parse(send(backend.client, systemPrompt, input, model), model, learningSummary)
    }

    /**
     * Rewrites already-polished [text] for [channel], following one [refinement] instruction.
     *
     * The prompt is `refine.txt` with the shared rules, the channel guidelines and the
     * refinement file. Only `polished_text` is read from the reply; any other key the model adds
     * is ignored, even when malformed.
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
        val systemPrompt = loadPrompt { assembler.assembleRefinement(refinement, channel) }
        val backend = backend()
        val model = backend.models.forTier(ModelRouting.pickTier(input))
        val raw = send(backend.client, systemPrompt, input, model)
        return polishedText(decodeObject(raw))
    }

    override suspend fun checkReady() {
        backend().client.checkAvailable()
    }

    /** Sends [systemPrompt] followed by [input] wrapped in `<draft>` tags, in one message. */
    private suspend fun send(
        client: LlmClient,
        systemPrompt: String,
        input: String,
        model: String,
    ): String = client.run("$systemPrompt\n\n${wrapDraft(input)}", model, timeout)

    companion object {
        const val MAX_INPUT_LENGTH = 20_000
        val DEFAULT_TIMEOUT: Duration = 120.seconds

        private val json = Json { ignoreUnknownKeys = true }
        private val closingDraftTag = Regex("</(draft)", RegexOption.IGNORE_CASE)

        /**
         * Wraps [text] in `<draft>` tags so the model treats it as material, not instructions.
         * A closing `</draft` inside the text gets a backslash (`<\/draft`), in any letter case,
         * so the author's text can't end the draft early. Mirrors `PolishService.wrapDraft`.
         */
        internal fun wrapDraft(text: String): String {
            val neutralized = closingDraftTag.replace(text, "<\\\\/$1")
            return "<draft>\n$neutralized\n</draft>"
        }

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

        private fun parse(
            raw: String,
            model: String,
            wantsSummary: Boolean,
        ): PolishResult {
            val response = decodeObject(raw)
            val polishedText = polishedText(response)
            val wasTranslated = isTruthy(response["was_translated"])
            val summary =
                if (wasTranslated || !wantsSummary) {
                    null
                } else {
                    decodeSummary(response["learning_summary"])
                }
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
