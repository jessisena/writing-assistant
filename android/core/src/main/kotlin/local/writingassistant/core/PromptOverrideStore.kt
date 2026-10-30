package local.writingassistant.core

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING

/** Why a prompt couldn't be saved. Mirrors `PromptValidationError` in `Contracts.swift`. */
sealed class PromptValidationException(
    override val message: String,
) : Exception(message) {
    data object Empty : PromptValidationException("A prompt can't be empty.")

    /** The text lacks [placeholder], which the file must keep. */
    data class MissingPlaceholder(
        val placeholder: String,
    ) : PromptValidationException(
            "This prompt must contain $placeholder so the ${insertedPart(placeholder)} can be " +
                "inserted.",
        )

    private companion object {
        fun insertedPart(placeholder: String): String =
            if (placeholder == PromptFile.INSTRUCTION_PLACEHOLDER) {
                "refinement instruction"
            } else {
                "channel guidelines"
            }
    }
}

/**
 * Prompt files the user edited, stored under [directory] with the bundled layout, on top of the
 * bundled [defaults]. Reading returns the edited copy when there is one, else the default.
 */
class PromptOverrideStore(
    private val directory: File,
    private val defaults: PromptReading,
) : PromptReading {
    override fun read(file: PromptFile): String {
        val override = overrideFile(file)
        return if (override.exists()) override.readText(Charsets.UTF_8) else defaults.read(file)
    }

    /** The bundled text of [file], ignoring any edit. */
    fun readDefault(file: PromptFile): String = defaults.read(file)

    /** Whether [file] has an edited copy. */
    fun isCustomized(file: PromptFile): Boolean = overrideFile(file).exists()

    /**
     * Stores [text] as the edited copy of [file]. Text identical to the default removes the edited
     * copy instead, so the file doesn't show as edited.
     *
     * @throws PromptValidationException when [text] is blank, or lacks the file's
     *   [PromptFile.requiredPlaceholder].
     * @throws java.io.IOException when the file can't be written.
     */
    fun save(
        file: PromptFile,
        text: String,
    ) {
        validate(file, text)
        if (text == readDefault(file)) {
            reset(file)
            return
        }
        val target = overrideFile(file).absoluteFile.toPath()
        val folder = Files.createDirectories(target.parent)
        val temp = Files.createTempFile(folder, ".prompt", ".tmp")
        try {
            Files.writeString(temp, text, Charsets.UTF_8)
            Files.move(temp, target, ATOMIC_MOVE, REPLACE_EXISTING)
        } finally {
            Files.deleteIfExists(temp)
        }
    }

    /**
     * Deletes the edited copy of [file], so the bundled default applies again.
     *
     * @throws java.io.IOException when the edited copy exists but can't be deleted.
     */
    fun reset(file: PromptFile) {
        Files.deleteIfExists(overrideFile(file).toPath())
    }

    private fun overrideFile(file: PromptFile) = File(directory, file.relativePath)

    private companion object {
        /** Mirrors `PromptFile.validate` in `Contracts.swift`. */
        fun validate(
            file: PromptFile,
            text: String,
        ) {
            if (text.isBlank()) {
                throw PromptValidationException.Empty
            }
            val placeholder = file.requiredPlaceholder
            if (placeholder != null && !text.contains(placeholder)) {
                throw PromptValidationException.MissingPlaceholder(placeholder)
            }
        }
    }
}
