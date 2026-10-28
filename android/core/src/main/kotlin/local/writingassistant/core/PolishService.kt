package local.writingassistant.core

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** Validate, route, assemble, call, parse. Mirrors `PolishService.swift`. */
class PolishService(
    private val client: ClaudeClient,
    private val prompts: PromptReading,
    private val timeout: Duration = DEFAULT_TIMEOUT,
) : Polishing {
    override suspend fun polish(
        text: String,
        channel: Channel,
    ): PolishResult = TODO("core worker ($client, $prompts, $timeout, $text, $channel)")

    override suspend fun refine(
        text: String,
        channel: Channel,
        refinement: Refinement,
    ): String = TODO("core worker ($text, $channel, $refinement)")

    override suspend fun checkReady(): Unit = TODO("core worker")

    companion object {
        const val MAX_INPUT_LENGTH = 20_000
        val DEFAULT_TIMEOUT: Duration = 120.seconds
    }
}
