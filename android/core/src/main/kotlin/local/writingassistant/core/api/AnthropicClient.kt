package local.writingassistant.core.api

import local.writingassistant.core.ClaudeClient
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import kotlin.time.Duration

/**
 * [ClaudeClient] backed by one `POST /v1/messages` call to the Anthropic API.
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
    ): String = TODO("client worker ($apiKey, $httpClient, $baseUrl, $prompt, $model, $timeout)")

    override suspend fun checkAvailable(): Unit = TODO("client worker")

    companion object {
        const val DEFAULT_BASE_URL = "https://api.anthropic.com/"
        const val ANTHROPIC_VERSION = "2023-06-01"
    }
}
