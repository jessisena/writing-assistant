package local.writingassistant.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import java.io.IOException

/**
 * Prompt files for pipeline tests. The assembled prompt is `SYSTEM <CHANNEL> RULES`; a
 * refinement reads `<REFINEMENT> INSTRUCTION`. Files in [missing] throw [IOException].
 */
class StubPromptReader(
    private val missing: Set<PromptFile> = emptySet(),
) : PromptReading {
    override fun read(file: PromptFile): String {
        if (file in missing) {
            throw IOException("${file.relativePath} is missing")
        }
        return when (file) {
            PromptFile.Global -> "  SYSTEM ${PromptFile.CHANNEL_PLACEHOLDER}\n"
            is PromptFile.ForChannel -> "\n${file.channel.id.uppercase()} RULES  "
            is PromptFile.ForRefinement -> "  ${file.refinement.id.uppercase()} INSTRUCTION \n"
        }
    }
}

fun summaryObject(): JsonObject =
    buildJsonObject {
        putJsonArray("corrections") {
            add(
                buildJsonObject {
                    put("original", "send me the report pls")
                    put("corrected", "please send me the report by end of day")
                    put(
                        "why",
                        "Avoid informal abbreviations in written professional communication.",
                    )
                },
            )
        }
        put("grammar_insight", "Spelling out polite words like 'please' signals professionalism.")
        putJsonArray("vocabulary") {
            add(
                buildJsonObject {
                    put("term", "by end of day")
                    put("meaning", "before the working day ends")
                    put("example", "Please submit your feedback by end of day.")
                },
            )
        }
    }

/** [summaryObject] with [key] added or replaced. */
fun summaryWith(
    key: String,
    value: JsonElement,
): JsonObject = JsonObject(summaryObject() + (key to value))

fun json(vararg fields: Pair<String, JsonElement>): String = JsonObject(fields.toMap()).toString()

val englishResponse =
    json(
        "detected_language" to JsonPrimitive("English"),
        "was_translated" to JsonPrimitive(false),
        "polished_text" to JsonPrimitive("Please send me the report by end of day."),
        "learning_summary" to summaryObject(),
    )

fun translatedResponse(language: String): String =
    json(
        "detected_language" to JsonPrimitive(language),
        "was_translated" to JsonPrimitive(true),
        "polished_text" to JsonPrimitive("Please send me the report by end of day."),
        "learning_summary" to JsonNull,
    )

/** A valid summary with the given `was_translated`; null leaves the key out. */
fun responseWithSummary(wasTranslated: JsonElement?): String {
    val fields =
        listOfNotNull(
            "polished_text" to JsonPrimitive("Hi"),
            "learning_summary" to summaryObject(),
            wasTranslated?.let { "was_translated" to it },
        )
    return json(*fields.toTypedArray())
}

val emptyArray: JsonElement = buildJsonArray {}
val emptyObject: JsonElement = buildJsonObject {}
val nonEmptyObject: JsonElement = buildJsonObject { put("a", 0) }

fun replying(vararg replies: String) = FakeClaudeClient(replies.map { Result.success(it) })

/** Runs [block] and returns what it threw; fails the test when it returns normally. */
suspend fun thrownBy(block: suspend () -> Unit): Throwable =
    runCatching { block() }.exceptionOrNull() ?: throw AssertionError("Expected an exception")
