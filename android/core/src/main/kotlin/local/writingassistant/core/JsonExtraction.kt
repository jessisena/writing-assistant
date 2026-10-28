package local.writingassistant.core

/** Locates the JSON object inside a model response. Mirrors `JSONExtraction.swift`. */
object JsonExtraction {
    /** Returns the JSON object text inside [raw], which may have a preamble or a code fence. */
    fun extractJsonText(raw: String): String = TODO("core worker: port JSONExtraction.swift ($raw)")
}
