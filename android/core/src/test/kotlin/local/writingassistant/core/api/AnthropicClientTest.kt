package local.writingassistant.core.api

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
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

class AnthropicClientTest {
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
        AnthropicClient(apiKey = { storedKey }, httpClient = httpClient, baseUrl = server.url("/"))

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
        client: AnthropicClient = client(),
        timeout: Duration = 5.seconds,
    ): String = client.run(prompt = "Fix this text", model = "claude-sonnet-5-5", timeout = timeout)

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

    @Test
    fun `run posts one user message with the required headers`() =
        runTest {
            enqueue(200, textResponse("Polished."))

            assertEquals("Polished.", runPolish())

            val request = takeRequest()
            assertEquals("POST", request.method)
            assertEquals("/v1/messages", request.url.encodedPath)
            assertEquals(API_KEY, request.headers["x-api-key"])
            assertEquals("2023-06-01", request.headers["anthropic-version"])
            assertTrue(request.headers["content-type"].orEmpty().startsWith("application/json"))
            val body = Json.parseToJsonElement(request.body!!.utf8()).jsonObject
            assertEquals(setOf("model", "max_tokens", "messages", "thinking"), body.keys)
            assertEquals("claude-sonnet-5-5", body["model"]!!.jsonPrimitive.content)
            assertEquals(
                "between_tools",
                body["thinking"]!!.jsonObject["type"]!!.jsonPrimitive.content,
            )
            assertTrue(body["max_tokens"]!!.jsonPrimitive.int > 0)
            val messages = body["messages"]!!.jsonArray
            assertEquals(1, messages.size)
            assertEquals("user", messages[0].jsonObject["role"]!!.jsonPrimitive.content)
            assertEquals("Fix this text", messages[0].jsonObject["content"]!!.jsonPrimitive.content)
        }

    @Test
    fun `run reads the key on every call`() =
        runTest {
            enqueue(200, textResponse("one"))
            enqueue(200, textResponse("two"))

            runPolish()
            storedKey = "sk-ant-rotated"
            runPolish()

            assertEquals(API_KEY, takeRequest().headers["x-api-key"])
            assertEquals("sk-ant-rotated", takeRequest().headers["x-api-key"])
        }

    @Test
    fun `run joins every text block and skips other block types`() =
        runTest {
            enqueue(
                200,
                """
                {"content": [
                  {"type": "text", "text": "Hello, "},
                  {"type": "thinking", "thinking": "", "signature": "abc"},
                  {"type": "text", "text": "world."}
                ], "stop_reason": "end_turn"}
                """.trimIndent(),
            )

            assertEquals("Hello, world.", runPolish())
        }

    @Test
    fun `malformed JSON is a bad format error`() =
        runTest {
            enqueue(200, "{not json")

            assertFails<PolishError.BadFormat> { runPolish() }
        }

    @Test
    fun `a response without content is a bad format error`() =
        runTest {
            enqueue(200, """{"id": "msg_1", "type": "message"}""")

            assertFails<PolishError.BadFormat> { runPolish() }
        }

    @Test
    fun `a response without a text block is a bad format error`() =
        runTest {
            enqueue(200, """{"content": [{"type": "thinking", "thinking": ""}]}""")

            assertFails<PolishError.BadFormat> { runPolish() }
        }

    @Test
    fun `401 is an invalid key`() =
        runTest {
            enqueue(401, errorBody("authentication_error", "invalid x-api-key"))

            assertFails<PolishError.InvalidApiKey> { runPolish() }
        }

    @Test
    fun `403 is an invalid key`() =
        runTest {
            enqueue(403, errorBody("permission_error", "Not allowed"))

            assertFails<PolishError.InvalidApiKey> { runPolish() }
        }

    @Test
    fun `400 about the credit balance is no credits`() =
        runTest {
            enqueue(400, errorBody("invalid_request_error", CREDIT_MESSAGE))

            assertFails<PolishError.NoCredits> { runPolish() }
        }

    @Test
    fun `402 billing error is no credits`() =
        runTest {
            enqueue(402, errorBody("billing_error", "Billing problem"))

            assertFails<PolishError.NoCredits> { runPolish() }
        }

    @Test
    fun `other 400 is an API failure with the server message`() =
        runTest {
            enqueue(400, errorBody("invalid_request_error", "max_tokens: must be positive"))

            val error = assertFails<PolishError.ApiFailed> { runPolish() }

            assertEquals(400, error.status)
            assertEquals("max_tokens: must be positive", error.detail)
        }

    @Test
    fun `429 503 and 529 are overloaded`() =
        runTest {
            for (status in listOf(429, 503, 529)) {
                enqueue(status, errorBody("overloaded_error", "Overloaded"))

                assertFails<PolishError.Overloaded> { runPolish() }
            }
        }

    @Test
    fun `500 with a JSON body reports the error message`() =
        runTest {
            enqueue(500, errorBody("api_error", "Internal server error"))

            val error = assertFails<PolishError.ApiFailed> { runPolish() }

            assertEquals(500, error.status)
            assertEquals("Internal server error", error.detail)
        }

    @Test
    fun `500 without a JSON body reports a body excerpt`() =
        runTest {
            enqueue(500, "<html>" + "x".repeat(1000) + "</html>")

            val error = assertFails<PolishError.ApiFailed> { runPolish() }

            assertTrue(error.detail.startsWith("<html>"))
            assertTrue(error.detail.length <= 200)
        }

    @Test
    fun `500 with an empty body still has a detail`() =
        runTest {
            enqueue(500, "")

            val error = assertFails<PolishError.ApiFailed> { runPolish() }

            assertTrue(error.detail.isNotBlank())
        }

    @Test
    fun `an error body echoing the key is redacted`() =
        runTest {
            enqueue(500, errorBody("api_error", "Something broke for $API_KEY"))

            val error = assertFails<PolishError.ApiFailed> { runPolish() }

            assertTrue(error.detail.contains("[redacted]"))
        }

    @Test
    fun `a slow response past the timeout is a timeout`() =
        runTest {
            server.enqueue(
                MockResponse
                    .Builder()
                    .body(textResponse("late"))
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
            val malformed =
                listOf("$API_KEY\u200B", "\u201C$API_KEY\u201D", "sk-ant-api03\n-test", "sk ant")
            for (key in malformed) {
                storedKey = key

                val error = assertFails<PolishError.MalformedApiKey> { runPolish() }
                assertFalse(error.message.contains("sk-ant"))
                assertFails<PolishError.MalformedApiKey> { client().checkAvailable() }
            }
            assertEquals(0, server.requestCount)
        }

    @Test
    fun `isWellFormedKey accepts printable ASCII only`() {
        assertTrue(isWellFormedKey(API_KEY))
        assertTrue(isWellFormedKey("!~"))
        assertFalse(isWellFormedKey(""))
        assertFalse(isWellFormedKey("sk\tant"))
        assertFalse(isWellFormedKey("sk-ant-é"))
        assertFalse(isWellFormedKey("sk-ant\u007F"))
    }

    @Test
    fun `a reply cut off at max_tokens is output too long`() =
        runTest {
            enqueue(200, textResponse("""{\"polished_text\": \"Hal""", stopReason = "max_tokens"))

            assertFails<PolishError.OutputTooLong> { runPolish() }
        }

    @Test
    fun `a refused request is a refusal error`() =
        runTest {
            enqueue(200, """{"content": [], "stop_reason": "refusal"}""")

            assertFails<PolishError.Refused> { runPolish() }
        }

    @Test
    fun `run asks for a 16k token reply`() =
        runTest {
            enqueue(200, textResponse("Polished."))

            runPolish()

            val body = Json.parseToJsonElement(takeRequest().body!!.utf8()).jsonObject
            assertEquals(16_000, body["max_tokens"]!!.jsonPrimitive.int)
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
                    .body(textResponse("never"))
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
    fun `haiku requests send no thinking field`() =
        runTest {
            enqueue(200, textResponse("Polished."))

            client().run("Fix this text", Provider.ANTHROPIC.models.small, 5.seconds)

            val body = Json.parseToJsonElement(takeRequest().body!!.utf8()).jsonObject
            assertEquals(setOf("model", "max_tokens", "messages"), body.keys)
        }

    @Test
    fun `checkAvailable sends a one-token Haiku request`() =
        runTest {
            enqueue(200, textResponse("Hi"))

            client().checkAvailable()

            val body = Json.parseToJsonElement(takeRequest().body!!.utf8()).jsonObject
            assertEquals(Provider.ANTHROPIC.models.small, body["model"]!!.jsonPrimitive.content)
            assertEquals(1, body["max_tokens"]!!.jsonPrimitive.int)
        }

    @Test
    fun `checkAvailable reports API failures like run`() =
        runTest {
            enqueue(401, errorBody("authentication_error", "invalid x-api-key"))
            enqueue(400, errorBody("invalid_request_error", CREDIT_MESSAGE))

            assertFails<PolishError.InvalidApiKey> { client().checkAvailable() }
            assertFails<PolishError.NoCredits> { client().checkAvailable() }
        }

    private companion object {
        const val API_KEY = "sk-ant-api03-test-secret-key"
        const val CREDIT_MESSAGE =
            "Your credit balance is too low to access the Anthropic API. " +
                "Please go to Plans & Billing to upgrade or purchase credits."

        fun textResponse(
            text: String,
            stopReason: String = "end_turn",
        ) = """{"id": "msg_1", "type": "message", "role": "assistant",
               "content": [{"type": "text", "text": "$text"}], "stop_reason": "$stopReason"}"""

        fun errorBody(
            type: String,
            message: String,
        ) = """{"type": "error", "error": {"type": "$type", "message": "$message"}}"""
    }
}
