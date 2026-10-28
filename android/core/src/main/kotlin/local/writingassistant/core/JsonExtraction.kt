package local.writingassistant.core

/** Locates the JSON object inside a model response. Mirrors `JSONExtraction.swift`. */
object JsonExtraction {
    private val FENCE = Regex("```(?:json)?\\s*(.*?)```", RegexOption.DOT_MATCHES_ALL)

    /**
     * Returns the JSON object text inside [raw], which may have a preamble or a code fence.
     *
     * The first fenced block wins; otherwise the slice from the first `{` to the last `}` is
     * used; otherwise the trimmed text is returned unchanged. The result is not validated.
     */
    fun extractJsonText(raw: String): String {
        val text = raw.trim()
        FENCE.find(text)?.let { return it.groupValues[1].trim() }
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start >= 0 && end > start) {
            return text.substring(start, end + 1)
        }
        return text
    }
}
