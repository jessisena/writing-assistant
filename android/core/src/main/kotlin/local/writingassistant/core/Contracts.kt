package local.writingassistant.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.time.Duration

// Shared API between the core implementations and the Android app. Mirrors
// Sources/WritingAssistantCore/Contracts.swift; keep the two in step.

enum class Channel(
    val id: String,
    val displayName: String,
    val shortName: String,
) {
    SLACK("slack", "Slack message", "Slack"),
    SLACK_INFORMAL("slack_informal", "Informal Slack message", "Casual Slack"),
    TALKING_POINTS("talking_points", "Sync / meeting talking points", "Talking points"),
    FORMAL("formal", "Formal document", "Formal doc"),
    AI_PROMPT("ai_prompt", "AI prompt", "AI prompt"),
    OTHER("other", "Other / general", "General"),
    ;

    companion object {
        fun fromId(id: String): Channel? = entries.firstOrNull { it.id == id }
    }
}

/** A quick follow-up edit applied to text that was already polished. */
enum class Refinement(
    val id: String,
    val displayName: String,
) {
    SHORTER("shorter", "Shorter"),
    MORE_CASUAL("more_casual", "More casual"),
    MORE_FORMAL("more_formal", "More formal"),
}

@Serializable
data class Correction(
    val original: String,
    val corrected: String,
    val why: String,
)

@Serializable
data class VocabularyItem(
    val term: String,
    val meaning: String,
    val example: String,
)

@Serializable
data class LearningSummary(
    val corrections: List<Correction>,
    @SerialName("grammar_insight") val grammarInsight: String,
    val vocabulary: List<VocabularyItem>,
) {
    val isEmpty: Boolean
        get() = corrections.isEmpty() && grammarInsight.isEmpty() && vocabulary.isEmpty()
}

data class PolishResult(
    val polishedText: String,
    /** Always null when [wasTranslated] is true (enforced by `PolishService`). */
    val learningSummary: LearningSummary?,
    val detectedLanguage: String,
    val wasTranslated: Boolean,
    val modelUsed: String,
)

/** Every failure the polish pipeline reports. [message] is shown to the user as is. */
sealed class PolishError(
    override val message: String,
) : Exception(message) {
    data object EmptyInput : PolishError("Please paste some text before processing.")

    data class InputTooLong(
        val limit: Int,
    ) : PolishError("Text is too long. The limit is $limit characters.")

    data object MissingApiKey : PolishError("Add your Anthropic API key in Settings to start.")

    data object InvalidApiKey :
        PolishError("Anthropic rejected the API key. Check it in Settings.")

    /** The key has a character outside printable ASCII, such as a zero-width space or a newline. */
    data object MalformedApiKey :
        PolishError("The API key contains characters that aren't allowed. Paste it again.")

    /** The device's secure key storage failed. [detail] names the failure, never the key. */
    data class KeyStorageFailed(
        val detail: String,
    ) : PolishError(
            "Couldn't access the secure key storage on this device. Try again, or clear and " +
                "re-enter the key.",
        )

    data object NoCredits :
        PolishError("Your Anthropic account is out of credits. Add some in the Console.")

    data object Overloaded : PolishError("Claude is busy right now. Please try again shortly.")

    data class Timeout(
        val seconds: Int,
    ) : PolishError("Claude took longer than $seconds seconds. Please try again.")

    data class Network(
        val detail: String,
    ) : PolishError("Couldn't reach Anthropic. Check your connection and try again.")

    data class ApiFailed(
        val status: Int,
        val detail: String,
    ) : PolishError("Claude returned an error (HTTP $status). Please try again.")

    /** Claude hit the output token limit, so the reply is incomplete. */
    data object OutputTooLong :
        PolishError("The reply was cut off because the text is too long. Try a shorter selection.")

    /** Claude's safety systems declined the request. */
    data object Refused :
        PolishError("Claude declined to process this text. Try rewording it.")

    data class BadFormat(
        val detail: String,
    ) : PolishError("Unexpected response format from Claude. Please try again.")

    data class PromptUnavailable(
        val detail: String,
    ) : PolishError("Couldn't read the bundled prompt files ($detail).")

    /** A failure outside the cases above. [detail] is the exception class, never its message. */
    data class Unexpected(
        val detail: String,
    ) : PolishError("Something went wrong ($detail). Please try again.")
}

sealed class PromptFile(
    /** Path relative to the prompts directory, e.g. `channels/slack.txt`. */
    val relativePath: String,
) {
    data object Global : PromptFile("polish.txt")

    data class ForChannel(
        val channel: Channel,
    ) : PromptFile("channels/${channel.id}.txt")

    data class ForRefinement(
        val refinement: Refinement,
    ) : PromptFile("refinements/${refinement.id}.txt")

    companion object {
        const val CHANNEL_PLACEHOLDER = "{{CHANNEL_GUIDELINES}}"
    }
}

/** Sends one prompt to Claude and returns the text of the reply. */
interface ClaudeClient {
    /**
     * Runs [prompt] on [model].
     *
     * @throws PolishError MissingApiKey, MalformedApiKey, InvalidApiKey, NoCredits, Overloaded,
     *   Timeout, Network, ApiFailed, OutputTooLong, Refused or BadFormat, or any error the key
     *   provider throws.
     */
    suspend fun run(
        prompt: String,
        model: String,
        timeout: Duration,
    ): String

    /** Makes the cheapest possible call to confirm the key works. Throws like [run]. */
    suspend fun checkAvailable()
}

/** Read-only access to the prompt files (bundled assets on Android, a directory in tests). */
fun interface PromptReading {
    /** @throws java.io.IOException when the file can't be read. */
    fun read(file: PromptFile): String
}

interface Polishing {
    /** Polishes (or translates, then polishes) [text] for [channel]. Throws [PolishError]. */
    suspend fun polish(
        text: String,
        channel: Channel,
    ): PolishResult

    /** Rewrites already-polished [text] with one extra instruction; returns only the new text. */
    suspend fun refine(
        text: String,
        channel: Channel,
        refinement: Refinement,
    ): String

    /** Throws [PolishError] when Claude can't be reached with the current key. */
    suspend fun checkReady()
}
