package local.writingassistant.core.api

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import local.writingassistant.core.LlmClient
import local.writingassistant.core.PolishError
import local.writingassistant.core.Provider
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * [LlmClient] backed by one `POST /v1/messages` call to the Anthropic API.
 *
 * Cancelling the calling coroutine cancels the HTTP call. The API key is redacted from every
 * error this client throws.
 *
 * @param apiKey Returns the current key, or null when none is stored. Read on every call.
 * @param baseUrl Overridden in tests to point at MockWebServer.
 */
class AnthropicClient(
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
            MessagesRequest(model, MAX_TOKENS, listOf(Message(prompt)), thinkingOff(model))
        val body = send(request, timeout)
        return extractText(body)
    }

    override suspend fun checkAvailable() {
        val request = MessagesRequest(Provider.ANTHROPIC.models.small, 1, listOf(Message("Hi")))
        send(request, CHECK_TIMEOUT)
    }

    private suspend fun send(
        payload: MessagesRequest,
        timeout: Duration,
    ): String {
        val key = apiKey()?.takeIf { it.isNotBlank() } ?: throw PolishError.MissingApiKey
        if (!isWellFormedKey(key)) throw PolishError.MalformedApiKey
        val request =
            Request
                .Builder()
                .url(baseUrl.newBuilder().addPathSegments("v1/messages").build())
                .header("x-api-key", key)
                .header("anthropic-version", ANTHROPIC_VERSION)
                .post(json.encodeToString(payload).toRequestBody(JSON_MEDIA_TYPE))
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
    private data class MessagesRequest(
        val model: String,
        @SerialName("max_tokens") val maxTokens: Int,
        val messages: List<Message>,
        val thinking: Thinking? = null,
    )

    @Serializable
    private data class Thinking(
        val type: String,
    )

    @Serializable
    private data class MessagesResponse(
        val content: List<ContentBlock>,
        @SerialName("stop_reason") val stopReason: String? = null,
    )

    @Serializable
    private data class ContentBlock(
        val type: String,
        val text: String? = null,
    )

    @Serializable
    private data class ErrorEnvelope(
        val error: ErrorBody,
    )

    @Serializable
    private data class ErrorBody(
        val message: String,
    )

    companion object {
        const val DEFAULT_BASE_URL = "https://api.anthropic.com/"
        const val ANTHROPIC_VERSION = "2023-06-01"

        /**
         * Output cap for polish and refine calls. Inputs are capped at 20k characters, and the
         * cap leaves room for long translations. 16k is the documented non-streaming
         * default and is within both models' output limits (Haiku 4.5: 64k, Sonnet 5.5: 128k).
         */
        private const val MAX_TOKENS = 16_000
        private const val EXCERPT_LENGTH = 200
        private val CHECK_TIMEOUT = 20.seconds
        private val OVERLOADED_STATUSES = setOf(429, 503, 529)
        private val JSON_MEDIA_TYPE = "application/json".toMediaType()
        private val json =
            Json {
                ignoreUnknownKeys = true
                encodeDefaults = true
                explicitNulls = false
            }

        /**
         * Turns thinking off, as the Mac app does with `MAX_THINKING_TOKENS=0`: it multiplied
         * latency several times over. Sonnet 5.5 thinks adaptively unless told otherwise and
         * rejects `disabled`, so it gets `between_tools`; Haiku 4.5 doesn't think by default.
         */
        private fun thinkingOff(model: String): Thinking? =
            if (model == Provider.ANTHROPIC.models.large) Thinking("between_tools") else null

        private fun extractText(body: String): String {
            val response =
                try {
                    json.decodeFromString<MessagesResponse>(body)
                } catch (e: IllegalArgumentException) {
                    throw PolishError.BadFormat("Unparseable response: ${e.message}")
                }
            when (response.stopReason) {
                "max_tokens" -> throw PolishError.OutputTooLong
                "refusal" -> throw PolishError.Refused
            }
            val texts = response.content.filter { it.type == "text" }.mapNotNull { it.text }
            if (texts.isEmpty()) throw PolishError.BadFormat("Response has no text content block")
            return texts.joinToString("")
        }

        private fun failureFor(
            reply: HttpReply,
            redactor: Redactor,
        ): PolishError {
            val message = errorMessage(reply.body)
            return when {
                reply.status == 401 || reply.status == 403 -> {
                    PolishError.InvalidApiKey
                }

                reply.status == 402 -> {
                    PolishError.NoCredits
                }

                reply.status == 400 &&
                    message?.contains("credit balance", ignoreCase = true) == true -> {
                    PolishError.NoCredits
                }

                reply.status in OVERLOADED_STATUSES -> {
                    PolishError.Overloaded
                }

                else -> {
                    PolishError.ApiFailed(
                        reply.status,
                        redactor.clean(message ?: excerpt(reply.body)),
                    )
                }
            }
        }

        private fun errorMessage(body: String): String? =
            try {
                json.decodeFromString<ErrorEnvelope>(body).error.message
            } catch (_: IllegalArgumentException) {
                null
            }

        private fun excerpt(body: String): String =
            body.trim().take(EXCERPT_LENGTH).ifEmpty {
                "Empty response body"
            }
    }
}
