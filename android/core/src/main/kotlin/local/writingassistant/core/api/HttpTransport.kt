package local.writingassistant.core.api

import kotlinx.coroutines.suspendCancellableCoroutine
import local.writingassistant.core.PolishError
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.io.InterruptedIOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.ceil
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.toJavaDuration

// HTTP plumbing shared by the provider clients.

/**
 * Returns whether [key] can be sent as an HTTP header: printable ASCII only, so no spaces,
 * newlines, zero-width characters or smart quotes picked up while pasting.
 */
fun isWellFormedKey(key: String): Boolean = key.isNotEmpty() && key.all { it in '!'..'~' }

internal class HttpReply(
    val status: Int,
    val body: String,
)

/** Removes the API key from text that may end up in an error message. */
internal class Redactor(
    private val key: String,
) {
    fun clean(text: String): String = text.replace(key, "[redacted]")
}

/**
 * Runs [request] on OkHttp's dispatcher threads with [timeout] for the whole call. Cancelling
 * the calling coroutine cancels the HTTP call.
 *
 * @throws PolishError.Timeout or [PolishError.Network] when the call fails before a response.
 */
internal suspend fun OkHttpClient.execute(
    request: Request,
    timeout: Duration,
    redactor: Redactor,
): HttpReply =
    suspendCancellableCoroutine { continuation ->
        val call = withTimeout(timeout).newCall(request)
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

private fun OkHttpClient.withTimeout(timeout: Duration): OkHttpClient {
    val javaTimeout = timeout.toJavaDuration()
    return newBuilder()
        .callTimeout(javaTimeout)
        .readTimeout(javaTimeout)
        .writeTimeout(javaTimeout)
        .build()
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
