package local.writingassistant.core.api

import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import local.writingassistant.core.ClaudeClient
import local.writingassistant.core.ModelRouting
import local.writingassistant.core.PolishError
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.io.InterruptedIOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.ceil
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.DurationUnit
import kotlin.time.toJavaDuration

/**
 * [ClaudeClient] backed by one `POST /v1/messages` call to the Anthropic API.
 *
 * The request runs on OkHttp's dispatcher threads, and cancelling the calling coroutine cancels
 * the HTTP call. The API key is redacted from every error this client throws.
 *
 * @param apiKey Returns the current key, or null when none is stored. Read on every call.
 * @param baseUrl Overridden in tests to point at MockWebServer.
 */
class AnthropicClient(
    private val apiKey: suspend () -> String?,
    private val httpClient: OkHttpClient = OkHttpClient(),
    private val baseUrl: HttpUrl = DEFAULT_BASE_URL.toHttpUrl(),
) : ClaudeClient {
    override suspend fun run(
        prompt: String,
        model: String,
        timeout: Duration,
    ): String {
        val body = send(MessagesRequest(model, MAX_TOKENS, listOf(Message(prompt))), timeout)
        return extractText(body)
    }

    override suspend fun checkAvailable() {
        send(MessagesRequest(ModelRouting.HAIKU_MODEL, 1, listOf(Message("Hi"))), CHECK_TIMEOUT)
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
        val reply = execute(request, timeout, redactor)
        if (reply.status !in 200..299) throw failureFor(reply, redactor)
        return reply.body
    }

    private suspend fun execute(
        request: Request,
        timeout: Duration,
        redactor: Redactor,
    ): HttpReply =
        suspendCancellableCoroutine { continuation ->
            val call = clientFor(timeout).newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(
                object : Callback {
                    override fun onFailure(
                        call: Call,
                        e: IOException,
                    ) {
                        continuation.resumeWithException(ioFailure(e, timeout, redactor))
                    }

                    override fun onResponse(
                        call: Call,
                        response: Response,
                    ) {
                        val reply =
                            try {
                                response.use { HttpReply(it.code, it.body.string()) }
                            } catch (e: IOException) {
                                continuation.resumeWithException(ioFailure(e, timeout, redactor))
                                return
                            }
                        continuation.resume(reply)
                    }
                },
            )
        }

    private fun clientFor(timeout: Duration): OkHttpClient {
        val javaTimeout = timeout.toJavaDuration()
        return httpClient
            .newBuilder()
            .callTimeout(javaTimeout)
            .readTimeout(javaTimeout)
            .writeTimeout(javaTimeout)
            .build()
    }

    private class HttpReply(
        val status: Int,
        val body: String,
    )

    private class Redactor(
        private val key: String,
    ) {
        fun clean(text: String): String = text.replace(key, "[redacted]")
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
         * cap also covers adaptive thinking on Sonnet. 16k is the documented non-streaming
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
            }

        /**
         * Returns whether [key] can be sent as an HTTP header: printable ASCII only, so no
         * spaces, newlines, zero-width characters or smart quotes picked up while pasting.
         */
        fun isWellFormedKey(key: String): Boolean = key.isNotEmpty() && key.all { it in '!'..'~' }

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

        private fun ioFailure(
            e: IOException,
            timeout: Duration,
            redactor: Redactor,
        ): PolishError =
            if (e is InterruptedIOException) {
                PolishError.Timeout(wholeSecondsRoundedUp(timeout))
            } else {
                PolishError.Network(redactor.clean(e.message ?: e.javaClass.simpleName))
            }

        private fun wholeSecondsRoundedUp(timeout: Duration): Int =
            ceil(timeout.toDouble(DurationUnit.SECONDS)).toInt()
    }
}
