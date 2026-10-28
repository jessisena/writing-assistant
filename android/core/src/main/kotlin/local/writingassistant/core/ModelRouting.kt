package local.writingassistant.core

/** Chooses the Claude model for a piece of text. Mirrors `ModelRouting.swift`. */
object ModelRouting {
    const val HAIKU_MODEL = "claude-haiku-4-5-20251001"
    const val SONNET_MODEL = "claude-sonnet-5-5"

    private const val MAX_HAIKU_WORDS = 60
    private const val MAX_NON_ASCII_RATIO = 0.02
    private const val MAX_ASCII_CODE_POINT = 127
    private const val MAX_ROMANCE_HITS = 1
    private val WORD_PUNCTUATION = ".,!?;:\"'".toCharArray()
    private val WHITESPACE = Regex("(?U)\\s+")

    /** Common Spanish and Portuguese stopwords, used only as a routing hint. */
    private val ROMANCE_STOPWORDS =
        (
            "el la los las un una de del en que por para con su sus al o es son hay como " +
                "también pero si no yo lo le se mi tu da do em com não mas ou já"
        ).split(" ").toSet()

    /**
     * Returns [HAIKU_MODEL] for short, confidently English text, otherwise [SONNET_MODEL].
     *
     * Short means at most 60 whitespace-separated words. Ambiguous or empty text gets Sonnet,
     * because routing short non-English text to Haiku is the costlier mistake.
     */
    fun pickModel(text: String): String =
        if (words(text).size <= MAX_HAIKU_WORDS && looksLikeEnglish(text)) {
            HAIKU_MODEL
        } else {
            SONNET_MODEL
        }

    private fun words(text: String): List<String> =
        text.split(WHITESPACE).filter { it.isNotEmpty() }

    private fun looksLikeEnglish(text: String): Boolean {
        val codePoints = text.codePoints().toArray()
        if (codePoints.isEmpty()) {
            return false
        }
        val nonAscii = codePoints.count { it > MAX_ASCII_CODE_POINT }
        if (nonAscii.toDouble() / codePoints.size > MAX_NON_ASCII_RATIO) {
            return false
        }
        val romanceHits =
            words(text.lowercase())
                .map { it.trim(*WORD_PUNCTUATION) }
                .count { it in ROMANCE_STOPWORDS }
        return romanceHits <= MAX_ROMANCE_HITS
    }
}
