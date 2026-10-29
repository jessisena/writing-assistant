package local.writingassistant.core.api

import local.writingassistant.core.LlmClient
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import kotlin.time.Duration

/**
 * [LlmClient] backed by Groq's OpenAI-compatible chat completions API.
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
    ): String = TODO("Implemented in the core worker")

    override suspend fun checkAvailable(): Unit = TODO("Implemented in the core worker")

    companion object {
        const val DEFAULT_BASE_URL = "https://api.groq.com/openai/"
    }
}
