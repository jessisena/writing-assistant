package local.writingassistant.core

/** Locates the JSON object inside a model response. Mirrors `JSONExtraction.swift`. */
object JsonExtraction {
    private const val FENCE = "```"
    private const val LANGUAGE_TAG = "json"

    /**
     * Returns the JSON object text inside [raw], which may have a preamble or a code fence.
     *
     * The first fenced block wins; otherwise the slice from the first `{` to the last `}` is
     * used; otherwise the trimmed text is returned unchanged. The result is not validated.
     */
    fun extractJsonText(raw: String): String {
        val text = raw.trim()
        fencedBlock(text)?.let { return it }
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start >= 0 && end > start) {
            return text.substring(start, end + 1)
        }
        return text
    }

    /**
     * Returns the trimmed body of the first fenced block, without a leading `json` tag, or null
     * when there is none. Uses plain string search rather than a regex so it behaves the same on
     * the JVM and on Android, whose regex engines disagree on what `\s` matches.
     */
    private fun fencedBlock(text: String): String? {
        val open = text.indexOf(FENCE)
        if (open < 0) return null
        val afterOpen = open + FENCE.length
        val close = text.indexOf(FENCE, afterOpen)
        if (close < 0) return null
        val tagged = text.startsWith(LANGUAGE_TAG, afterOpen)
        val bodyStart = if (tagged) afterOpen + LANGUAGE_TAG.length else afterOpen
        return text.substring(bodyStart, close).trim()
    }
}
