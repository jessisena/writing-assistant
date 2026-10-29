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

    data object MissingApiKey : PolishError("Add your API key in Settings to start.")

    data object InvalidApiKey : PolishError("The API key was rejected. Check it in Settings.")

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

    /** Only Anthropic reports this, so the message names it. */
    data object NoCredits :
        PolishError("Your Anthropic account is out of credits. Add some in the Console.")

    /** The provider is overloaded, or the request hit a rate or tokens-per-minute limit. */
    data object Overloaded :
        PolishError("The AI service is busy or you've hit its rate limit. Try again shortly.")

    /** The provider's per-request token limit is lower than this text needs, so retrying fails. */
    data object TooLongForProvider :
        PolishError(
            "This text is too long for the selected provider's limits. Try a shorter selection " +
                "or switch provider in Settings.",
        )

    data class Timeout(
        val seconds: Int,
    ) : PolishError("The AI service took longer than $seconds seconds. Please try again.")

    data class Network(
        val detail: String,
    ) : PolishError("Couldn't reach the AI service. Check your connection and try again.")

    data class ApiFailed(
        val status: Int,
        val detail: String,
    ) : PolishError("The AI service returned an error (HTTP $status). Please try again.")

    /** The model hit the output token limit, so the reply is incomplete. */
    data object OutputTooLong :
        PolishError("The reply was cut off because the text is too long. Try a shorter selection.")

    /** The provider's safety systems declined the request. */
    data object Refused :
        PolishError("The AI service declined to process this text. Try rewording it.")

    data class BadFormat(
        val detail: String,
    ) : PolishError("The AI service sent a reply in an unexpected format. Please try again.")

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

/** Which of a provider's two models handles a piece of text; see [ModelRouting.pickTier]. */
enum class ModelTier {
    SMALL,
    LARGE,
}

/** A provider's fast model for short English text and its stronger model for everything else. */
data class Models(
    val small: String,
    val large: String,
) {
    fun forTier(tier: ModelTier): String =
        when (tier) {
            ModelTier.SMALL -> small
            ModelTier.LARGE -> large
        }
}

/** An LLM service the user can pick in Settings, each with its own API key. */
enum class Provider(
    /** Stable identifier used in storage keys; never change it. */
    val id: String,
    val displayName: String,
    /** Where the user creates an API key. */
    val keyUrl: String,
    val models: Models,
) {
    ANTHROPIC(
        "anthropic",
        "Anthropic",
        "https://console.anthropic.com/settings/keys",
        Models(small = "claude-haiku-4-5-20251001", large = "claude-sonnet-5-5"),
    ),
    GROQ(
        "groq",
        "Groq",
        "https://console.groq.com/keys",
        Models(small = "openai/gpt-oss-20b", large = "openai/gpt-oss-120b"),
    ),
    ;

    companion object {
        fun fromId(id: String): Provider? = entries.firstOrNull { it.id == id }
    }
}

/** The client and models that handle one request. */
data class Backend(
    val client: LlmClient,
    val models: Models,
)

/** Sends one prompt to an LLM provider and returns the text of the reply. */
interface LlmClient {
    /**
     * Runs [prompt] on [model].
     *
     * @throws PolishError MissingApiKey, MalformedApiKey, InvalidApiKey, NoCredits, Overloaded,
     *   TooLongForProvider, Timeout, Network, ApiFailed, OutputTooLong, Refused or BadFormat, or
     *   any error the key provider throws.
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

    /** Throws [PolishError] when the current provider can't be reached with its key. */
    suspend fun checkReady()
}
