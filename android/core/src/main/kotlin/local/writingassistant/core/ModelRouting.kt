package local.writingassistant.core

/** Chooses the Claude model for a piece of text. Mirrors `ModelRouting.swift`. */
object ModelRouting {
    const val HAIKU_MODEL = "claude-haiku-4-5-20251001"
    const val SONNET_MODEL = "claude-sonnet-5-5"

    /** Returns [HAIKU_MODEL] for short, confidently English text, otherwise [SONNET_MODEL]. */
    fun pickModel(text: String): String = TODO("core worker: port ModelRouting.swift ($text)")
}
