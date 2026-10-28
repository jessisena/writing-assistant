package local.writingassistant.core

import kotlin.time.Duration

/** Scripted [ClaudeClient] for tests: returns [replies] in order and records each call. */
class FakeClaudeClient(
    replies: List<Result<String>> = emptyList(),
) : ClaudeClient {
    data class Call(
        val prompt: String,
        val model: String,
        val timeout: Duration,
    )

    private val pending = ArrayDeque(replies)
    val calls = mutableListOf<Call>()

    /** Thrown by [checkAvailable] when set. */
    var availabilityError: PolishError? = null

    override suspend fun run(
        prompt: String,
        model: String,
        timeout: Duration,
    ): String {
        calls += Call(prompt, model, timeout)
        val reply = pending.removeFirstOrNull() ?: error("FakeClaudeClient has no reply left")
        return reply.getOrThrow()
    }

    override suspend fun checkAvailable() {
        availabilityError?.let { throw it }
    }
}
