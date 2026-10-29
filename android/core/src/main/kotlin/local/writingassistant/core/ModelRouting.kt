package local.writingassistant.core

/**
 * Chooses the model tier for a piece of text. The heuristic mirrors `ModelRouting.swift`, which
 * returns a Claude model ID where this returns a tier, so each provider maps it to its own model.
 */
object ModelRouting {
    private const val MAX_SMALL_WORDS = 60
    private const val MAX_NON_ASCII_RATIO = 0.02
    private const val MAX_ASCII_CODE_POINT = 127
    private const val MAX_ROMANCE_HITS = 1
    private val WORD_PUNCTUATION = ".,!?;:\"'".toCharArray()

    /** Common Spanish and Portuguese stopwords, used only as a routing hint. */
    private val ROMANCE_STOPWORDS =
        (
            "el la los las un una de del en que por para con su sus al o es son hay como " +
                "también pero si no yo lo le se mi tu da do em com não mas ou já"
        ).split(" ").toSet()

    /**
     * Returns [ModelTier.SMALL] for short, confidently English text, otherwise [ModelTier.LARGE].
     *
     * Short means at most 60 whitespace-separated words. Ambiguous or empty text gets the large
     * model, because routing short non-English text to the small one is the costlier mistake.
     */
    fun pickTier(text: String): ModelTier =
        if (words(text).size <= MAX_SMALL_WORDS && looksLikeEnglish(text)) {
            ModelTier.SMALL
        } else {
            ModelTier.LARGE
        }

    // Char.isWhitespace covers Unicode whitespace on every platform; a `\s` regex doesn't
    // (ASCII-only on the JVM, and Android's ICU engine rejects the `(?U)` flag).
    private fun words(text: String): List<String> =
        text
            .map { if (it.isWhitespace()) ' ' else it }
            .joinToString("")
            .split(' ')
            .filter { it.isNotEmpty() }

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
