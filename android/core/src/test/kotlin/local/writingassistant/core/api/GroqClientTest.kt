package local.writingassistant.core.api

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import local.writingassistant.core.PolishError
import local.writingassistant.core.Provider
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.Call
import okhttp3.EventListener
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

class GroqClientTest {
    private val server = MockWebServer()
    private var storedKey: String? = API_KEY

    @Before
    fun setUp() {
        server.start()
    }

    @After
    fun tearDown() {
        server.close()
    }

    private fun client(httpClient: OkHttpClient = OkHttpClient()) =
        GroqClient(apiKey = { storedKey }, httpClient = httpClient, baseUrl = server.url("/"))

    private fun enqueue(
        status: Int,
        body: String,
    ) {
        server.enqueue(
            MockResponse
                .Builder()
                .code(status)
                .body(body)
                .build(),
        )
    }

    private suspend fun runPolish(
        client: GroqClient = client(),
        model: String = Provider.GROQ.models.large,
        timeout: Duration = 5.seconds,
    ): String =
        client.run(prompt = "Fix this text, reply in JSON", model = model, timeout = timeout)

    private suspend inline fun <reified T : PolishError> assertFails(
        noinline block: suspend () -> Unit,
    ): T {
        try {
            block()
        } catch (e: PolishError) {
            assertTrue("Expected ${T::class.simpleName} but got $e", e is T)
            assertFalse("Error leaks the API key: $e", e.toString().contains(API_KEY))
            assertFalse("Error message leaks the API key", e.message.contains(API_KEY))
            return e as T
        }
        fail("Expected ${T::class.simpleName} but nothing was thrown")
        error("unreachable")
    }

    private fun takeRequest(): RecordedRequest =
        server.takeRequest(5, TimeUnit.SECONDS) ?: error("No request")

    private fun takeBody(): JsonObject =
        Json.parseToJsonElement(takeRequest().body!!.utf8()).jsonObject

    @Test
    fun `run posts one user message in JSON mode with a bearer key`() =
        runTest {
            enqueue(200, chatResponse("""{\"polished_text\": \"Polished.\"}"""))

            assertEquals("""{"polished_text": "Polished."}""", runPolish())

            val request = takeRequest()
            assertEquals("POST", request.method)
            assertEquals("/v1/chat/completions", request.url.encodedPath)
            assertEquals("Bearer $API_KEY", request.headers["Authorization"])
            assertTrue(request.headers["content-type"].orEmpty().startsWith("application/json"))
            val body = Json.parseToJsonElement(request.body!!.utf8()).jsonObject
            assertEquals(Provider.GROQ.models.large, body["model"]!!.jsonPrimitive.content)
            assertEquals(
                "json_object",
                body["response_format"]!!.jsonObject["type"]!!.jsonPrimitive.content,
            )
            val messages = body["messages"]!!.jsonArray
            assertEquals(1, messages.size)
            assertEquals("user", messages[0].jsonObject["role"]!!.jsonPrimitive.content)
            assertEquals(
                "Fix this text, reply in JSON",
                messages[0].jsonObject["content"]!!.jsonPrimitive.content,
            )
        }

    @Test
    fun `run caps the reply to fit the free tier's tokens per minute`() =
        runTest {
            enqueue(200, chatResponse("{}"))

            runPolish()

            val maxTokens = takeBody()["max_completion_tokens"]!!.jsonPrimitive.int
            assertEquals(4_096, maxTokens)
        }

    @Test
    fun `gpt-oss models reason with low effort and return no reasoning`() =
        runTest {
            for (model in listOf(Provider.GROQ.models.small, Provider.GROQ.models.large)) {
                enqueue(200, chatResponse("{}"))

                runPolish(model = model)

                val body = takeBody()
                assertEquals("low", body["reasoning_effort"]!!.jsonPrimitive.content)
                assertFalse(body["include_reasoning"]!!.jsonPrimitive.boolean)
            }
        }

    @Test
    fun `non-reasoning models get no reasoning fields`() =
        runTest {
            enqueue(200, chatResponse("{}"))

            runPolish(model = "llama-3.3-70b-versatile")

            assertEquals(
                setOf("model", "max_completion_tokens", "messages", "response_format"),
                takeBody().keys,
            )
        }

    @Test
    fun `run reads the key on every call`() =
        runTest {
            enqueue(200, chatResponse("one"))
            enqueue(200, chatResponse("two"))

            runPolish()
            storedKey = "gsk-test-rotated"
            runPolish()

            assertEquals("Bearer $API_KEY", takeRequest().headers["Authorization"])
            assertEquals("Bearer gsk-test-rotated", takeRequest().headers["Authorization"])
        }

    @Test
    fun `a reply cut off at the token cap is output too long`() =
        runTest {
            enqueue(200, chatResponse("""{\"polished_text\": \"Hal""", finishReason = "length"))

            assertFails<PolishError.OutputTooLong> { runPolish() }
        }

    @Test
    fun `malformed JSON is a bad format error`() =
        runTest {
            enqueue(200, "{not json")

            assertFails<PolishError.BadFormat> { runPolish() }
        }

    @Test
    fun `a response without choices is a bad format error`() =
        runTest {
            enqueue(200, """{"id": "chatcmpl-1", "object": "chat.completion"}""")
            enqueue(200, """{"id": "chatcmpl-1", "choices": []}""")

            assertFails<PolishError.BadFormat> { runPolish() }
            assertFails<PolishError.BadFormat> { runPolish() }
        }

    @Test
    fun `a choice with null or empty content is a bad format error`() =
        runTest {
            enqueue(200, """{"choices": [{"message": {"role": "assistant", "content": null}}]}""")
            enqueue(200, chatResponse(""))
            enqueue(200, """{"choices": [{"finish_reason": "stop"}]}""")

            repeat(3) { assertFails<PolishError.BadFormat> { runPolish() } }
        }

    @Test
    fun `JSON mode validation failure is a bad format error`() =
        runTest {
            enqueue(
                400,
                """{"error": {"message": "Failed to generate JSON. Please adjust your prompt.",
                   "type": "invalid_request_error", "code": "json_validate_failed",
                   "failed_generation": "Sure! Here is your text"}}""",
            )

            val error = assertFails<PolishError.BadFormat> { runPolish() }

            assertFalse(error.detail.contains("Sure!"))
        }

    @Test
    fun `401 and 403 are an invalid key`() =
        runTest {
            enqueue(401, errorBody("Invalid API Key", "invalid_api_key"))
            enqueue(403, errorBody("Forbidden", null))

            assertFails<PolishError.InvalidApiKey> { runPolish() }
            assertFails<PolishError.InvalidApiKey> { runPolish() }
        }

    @Test
    fun `429 413 and 503 are overloaded`() =
        runTest {
            for (status in listOf(429, 413, 503)) {
                enqueue(status, errorBody("Rate limit reached for model", "rate_limit_exceeded"))

                assertFails<PolishError.Overloaded> { runPolish() }
            }
        }

    @Test
    fun `other 400 is an API failure with the server message`() =
        runTest {
            enqueue(400, errorBody("max_completion_tokens must be positive", null))

            val error = assertFails<PolishError.ApiFailed> { runPolish() }

            assertEquals(400, error.status)
            assertEquals("max_completion_tokens must be positive", error.detail)
        }

    @Test
    fun `500 and 502 are API failures`() =
        runTest {
            enqueue(500, errorBody("Internal server error", null))
            enqueue(502, "<html>" + "x".repeat(1000) + "</html>")

            val internal = assertFails<PolishError.ApiFailed> { runPolish() }
            val gateway = assertFails<PolishError.ApiFailed> { runPolish() }

            assertEquals(500, internal.status)
            assertEquals("Internal server error", internal.detail)
            assertEquals(502, gateway.status)
            assertTrue(gateway.detail.startsWith("<html>"))
            assertTrue(gateway.detail.length <= 200)
        }

    @Test
    fun `an error body echoing the key is redacted`() =
        runTest {
            enqueue(404, errorBody("No such key $API_KEY", "model_not_found"))

            val error = assertFails<PolishError.ApiFailed> { runPolish() }

            assertTrue(error.detail.contains("[redacted]"))
        }

    @Test
    fun `a slow response past the timeout is a timeout`() =
        runTest {
            server.enqueue(
                MockResponse
                    .Builder()
                    .body(chatResponse("late"))
                    .headersDelay(3, TimeUnit.SECONDS)
                    .build(),
            )

            val error = assertFails<PolishError.Timeout> { runPolish(timeout = 300.milliseconds) }

            assertEquals(1, error.seconds)
        }

    @Test
    fun `an unreachable server is a network error`() =
        runTest {
            val client = client()
            server.close()

            assertFails<PolishError.Network> { runPolish(client) }
        }

    @Test
    fun `a missing or blank key fails without a request`() =
        runTest {
            for (key in listOf(null, "", "   ")) {
                storedKey = key

                assertFails<PolishError.MissingApiKey> { runPolish() }
                assertFails<PolishError.MissingApiKey> { client().checkAvailable() }
            }
            assertEquals(0, server.requestCount)
        }

    @Test
    fun `a key with characters that can't go in a header fails without a request`() =
        runTest {
            val zeroWidthSpace = Char(0x200B)
            val smartQuotes = Char(0x201C) to Char(0x201D)
            val malformed =
                listOf(
                    "$API_KEY$zeroWidthSpace",
                    "${smartQuotes.first}$API_KEY${smartQuotes.second}",
                    "gsk\n-test",
                    "gsk x",
                )
            for (key in malformed) {
                storedKey = key

                val error = assertFails<PolishError.MalformedApiKey> { runPolish() }
                assertFalse(error.message.contains("gsk"))
                assertFails<PolishError.MalformedApiKey> { client().checkAvailable() }
            }
            assertEquals(0, server.requestCount)
        }

    @Test
    fun `cancelling the coroutine cancels the HTTP call`() =
        runTest {
            val canceled = CountDownLatch(1)
            val httpClient =
                OkHttpClient
                    .Builder()
                    .eventListener(
                        object : EventListener() {
                            override fun canceled(call: Call) = canceled.countDown()
                        },
                    ).build()
            server.enqueue(
                MockResponse
                    .Builder()
                    .body(chatResponse("never"))
                    .headersDelay(30, TimeUnit.SECONDS)
                    .build(),
            )

            val pending =
                async(Dispatchers.Default) { runPolish(client(httpClient), timeout = 60.seconds) }
            withContext(Dispatchers.IO) { takeRequest() }
            pending.cancel()

            val wasCanceled = withContext(Dispatchers.IO) { canceled.await(5, TimeUnit.SECONDS) }
            assertTrue("OkHttp call was not cancelled", wasCanceled)
            assertTrue(pending.isCancelled)
        }

    @Test
    fun `checkAvailable sends a one-token small model request without JSON mode`() =
        runTest {
            enqueue(200, chatResponse("", finishReason = "length"))

            client().checkAvailable()

            val body = takeBody()
            assertEquals(Provider.GROQ.models.small, body["model"]!!.jsonPrimitive.content)
            assertEquals(1, body["max_completion_tokens"]!!.jsonPrimitive.int)
            assertFalse(body.containsKey("response_format"))
        }

    @Test
    fun `checkAvailable reports API failures like run`() =
        runTest {
            enqueue(401, errorBody("Invalid API Key", "invalid_api_key"))
            enqueue(429, errorBody("Rate limit reached", "rate_limit_exceeded"))

            assertFails<PolishError.InvalidApiKey> { client().checkAvailable() }
            assertFails<PolishError.Overloaded> { client().checkAvailable() }
        }

    private companion object {
        const val API_KEY = "gsk-test-secret-key"

        fun chatResponse(
            content: String,
            finishReason: String = "stop",
        ) = """{"id": "chatcmpl-1", "object": "chat.completion", "model": "openai/gpt-oss-120b",
               "choices": [{"index": 0, "message": {"role": "assistant", "content": "$content"},
               "finish_reason": "$finishReason"}]}"""

        fun errorBody(
            message: String,
            code: String?,
        ): String {
            val codeField = code?.let { """, "code": "$it"""" }.orEmpty()
            val type = "invalid_request_error"
            return """{"error": {"message": "$message", "type": "$type"$codeField}}"""
        }
    }
}
