package local.writingassistant.core

import java.io.File

/** Why a prompt couldn't be saved. Mirrors `PromptValidationError` in `Contracts.swift`. */
sealed class PromptValidationException(
    override val message: String,
) : Exception(message) {
    data object Empty : PromptValidationException("A prompt can't be empty.")

    data object MissingPlaceholder :
        PromptValidationException(
            "Global rules must contain ${PromptFile.CHANNEL_PLACEHOLDER} so the channel " +
                "guidelines can be inserted.",
        )
}

/**
 * Prompt files the user edited, stored under [directory] with the bundled layout, on top of the
 * bundled [defaults]. Reading returns the edited copy when there is one, else the default.
 */
class PromptOverrideStore(
    private val directory: File,
    private val defaults: PromptReading,
) : PromptReading {
    override fun read(file: PromptFile): String = TODO()

    /** The bundled text of [file], ignoring any edit. */
    fun readDefault(file: PromptFile): String = TODO()

    /** Whether [file] has an edited copy. */
    fun isCustomized(file: PromptFile): Boolean = TODO()

    /**
     * Stores [text] as the edited copy of [file].
     *
     * @throws PromptValidationException when [text] is blank, or is the global file without
     *   [PromptFile.CHANNEL_PLACEHOLDER].
     * @throws java.io.IOException when the file can't be written.
     */
    fun save(
        file: PromptFile,
        text: String,
    ): Unit = TODO()

    /** Deletes the edited copy of [file], so the bundled default applies again. */
    fun reset(file: PromptFile): Unit = TODO()
}
