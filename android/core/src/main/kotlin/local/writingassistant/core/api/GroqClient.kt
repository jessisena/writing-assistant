package local.writingassistant.core.api

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import local.writingassistant.core.LlmClient
import local.writingassistant.core.PolishError
import local.writingassistant.core.Provider
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * [LlmClient] backed by one `POST /v1/chat/completions` call to Groq's OpenAI-compatible API.
 *
 * Cancelling the calling coroutine cancels the HTTP call. The API key is redacted from every
 * error this client throws.
 *
 * @param apiKey Returns the current key, or null when none is stored. Read on every call.
 * @param baseUrl Overridden in tests to point at MockWebServer.
 */
class GroqClient(
    private val apiKey: suspend () -> String?,
    private val httpClient: OkHttpClient = OkHttpClient(),
    private val baseUrl: HttpUrl = DEFAULT_BASE_URL.toHttpUrl(),
) : LlmClient {
    override suspend fun run(
        prompt: String,
        model: String,
        timeout: Duration,
    ): String {
        val request =
            chatRequest(model, MAX_COMPLETION_TOKENS, prompt, ResponseFormat(JSON_OBJECT))
        val body = send(request, timeout)
        return extractText(body)
    }

    override suspend fun checkAvailable() {
        send(chatRequest(Provider.GROQ.models.small, 1, "Hi", responseFormat = null), CHECK_TIMEOUT)
    }

    private suspend fun send(
        payload: ChatRequest,
        timeout: Duration,
    ): String {
        val key = apiKey()?.takeIf { it.isNotBlank() } ?: throw PolishError.MissingApiKey
        if (!isWellFormedKey(key)) throw PolishError.MalformedApiKey
        val request =
            Request
                .Builder()
                .url(baseUrl.newBuilder().addPathSegments("v1/chat/completions").build())
                .header("Authorization", "Bearer $key")
                .post(apiJson.encodeToString(payload).toRequestBody(JSON_MEDIA_TYPE))
                .build()
        val redactor = Redactor(key)
        val reply = httpClient.execute(request, timeout, redactor)
        if (reply.status !in 200..299) throw failureFor(reply, redactor)
        return reply.body
    }

    @Serializable
    private data class Message(
        val content: String,
        val role: String = "user",
    )

    @Serializable
    private data class ResponseFormat(
        val type: String,
    )

    @Serializable
    private data class ChatRequest(
        val model: String,
        @SerialName("max_completion_tokens") val maxCompletionTokens: Int,
        val messages: List<Message>,
        @SerialName("response_format") val responseFormat: ResponseFormat? = null,
        @SerialName("reasoning_effort") val reasoningEffort: String? = null,
        @SerialName("include_reasoning") val includeReasoning: Boolean? = null,
    )

    @Serializable
    private data class ChatResponse(
        val choices: List<Choice>,
    )

    @Serializable
    private data class Choice(
        val message: ResponseMessage? = null,
        @SerialName("finish_reason") val finishReason: String? = null,
    )

    @Serializable
    private data class ResponseMessage(
        val content: String? = null,
    )

    @Serializable
    private data class ErrorEnvelope(
        val error: ErrorBody,
    )

    /** Groq also sends `failed_generation` with the model's text; it's ignored on purpose. */
    @Serializable
    private data class ErrorBody(
        val message: String,
        val code: String? = null,
    )

    companion object {
        const val DEFAULT_BASE_URL = "https://api.groq.com/openai/"

        /**
         * Output cap for polish and refine calls. Groq's free tier allows 8k tokens a minute
         * for both models and counts this cap against that budget before the reply starts, so
         * a 16k cap like Anthropic's would fail every request with 413. 4k plus a typical
         * 1.5k-2.5k token prompt fits, and stays well under both models' 65k output limit.
         */
        private const val MAX_COMPLETION_TOKENS = 4_096
        private const val JSON_OBJECT = "json_object"
        private const val JSON_VALIDATE_FAILED = "json_validate_failed"
        private val CHECK_TIMEOUT = 20.seconds
        private val OVERLOADED_STATUSES = setOf(413, 429, 503)

        private fun chatRequest(
            model: String,
            maxCompletionTokens: Int,
            prompt: String,
            responseFormat: ResponseFormat?,
        ): ChatRequest {
            val reasons = isReasoningModel(model)
            return ChatRequest(
                model = model,
                maxCompletionTokens = maxCompletionTokens,
                messages = listOf(Message(prompt)),
                responseFormat = responseFormat,
                reasoningEffort = if (reasons) "low" else null,
                includeReasoning = if (reasons) false else null,
            )
        }

        /**
         * gpt-oss always reasons, so it gets the lowest effort Groq allows (`low`) to keep
         * latency down, as thinking is turned off on Claude. `include_reasoning: false` leaves
         * the reasoning out of the reply; it never appears in `content` for these models.
         */
        private fun isReasoningModel(model: String): Boolean = model.startsWith("openai/gpt-oss-")

        private fun extractText(body: String): String {
            val response =
                try {
                    apiJson.decodeFromString<ChatResponse>(body)
                } catch (e: IllegalArgumentException) {
                    throw PolishError.BadFormat("Unparseable response: ${e.message}")
                }
            val choice =
                response.choices.firstOrNull()
                    ?: throw PolishError.BadFormat("Response has no choices")
            if (choice.finishReason == "length") throw PolishError.OutputTooLong
            val content = choice.message?.content
            if (content.isNullOrEmpty()) throw PolishError.BadFormat("Response has no content")
            return content
        }

        private fun failureFor(
            reply: HttpReply,
            redactor: Redactor,
        ): PolishError {
            val error = errorBody(reply.body)
            return when {
                reply.status == 401 || reply.status == 403 -> {
                    PolishError.InvalidApiKey
                }

                reply.status in OVERLOADED_STATUSES -> {
                    PolishError.Overloaded
                }

                reply.status == 400 && error?.code == JSON_VALIDATE_FAILED -> {
                    PolishError.BadFormat("Groq couldn't produce valid JSON")
                }

                else -> {
                    PolishError.ApiFailed(
                        reply.status,
                        redactor.clean(error?.message ?: bodyExcerpt(reply.body)),
                    )
                }
            }
        }

        private fun errorBody(body: String): ErrorBody? =
            try {
                apiJson.decodeFromString<ErrorEnvelope>(body).error
            } catch (_: IllegalArgumentException) {
                null
            }
    }
}
