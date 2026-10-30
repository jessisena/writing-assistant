package local.writingassistant.core

/**
 * The context the author writes in. Each mode has its own channels, language policy, learning
 * summary setting and tone (`prompts/modes/<id>.txt`). Mirrors `Mode` in `Mode.swift`.
 */
enum class Mode(
    /** Stable identifier used in storage and the history file; never change it. */
    val id: String,
    val displayName: String,
) {
    WORK("work", "Work"),
    PERSONAL("personal", "Personal"),
    ;

    /** The other mode, which the mode toggle switches to. */
    val toggled: Mode get() = if (this == WORK) PERSONAL else WORK

    companion object {
        fun fromId(id: String): Mode? = entries.firstOrNull { it.id == id }
    }
}

/** Which language the polished text is written in. Mirrors `OutputLanguage` in `Mode.swift`. */
enum class OutputLanguage(
    /** Stable identifier used in storage; never change it. */
    val id: String,
    val displayName: String,
    /** The prompt file name under `languages/`. */
    val fileName: String,
) {
    /** Translate a non-English draft to English first. */
    ENGLISH("english", "English", "english"),

    /** Write in the draft's language; never translate. */
    SAME_AS_INPUT("sameAsInput", "Same as input", "same_as_input"),
    ;

    companion object {
        fun fromId(id: String): OutputLanguage? = entries.firstOrNull { it.id == id }
    }
}

/**
 * What a polish request asks for besides the text and the channel. Mirrors `PolishOptions`.
 *
 * @property includesLearningSummary Whether to ask for the English learning summary. Even when
 *   true, a result only gets one for English input (see [allowsLearningSummary]).
 */
data class PolishOptions(
    val mode: Mode,
    val outputLanguage: OutputLanguage,
    val includesLearningSummary: Boolean,
) {
    /**
     * Whether a reply with these language fields may carry a learning summary.
     *
     * The summary coaches English only. A translation never gets one. Under
     * [OutputLanguage.ENGLISH] an untranslated draft is English by definition; under
     * [OutputLanguage.SAME_AS_INPUT] the draft can be in any language, so the reply must name
     * English (a missing language counts as not English).
     */
    fun allowsLearningSummary(
        detectedLanguage: String?,
        wasTranslated: Boolean,
    ): Boolean {
        if (!includesLearningSummary || wasTranslated) return false
        return when (outputLanguage) {
            OutputLanguage.ENGLISH -> true
            OutputLanguage.SAME_AS_INPUT -> isEnglish(detectedLanguage)
        }
    }

    companion object {
        /** True for "English" and variants such as "english" or "English (US)". */
        internal fun isEnglish(language: String?): Boolean =
            language?.trim()?.lowercase()?.startsWith("english") == true
    }
}
