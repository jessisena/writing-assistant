package local.writingassistant.core

import java.io.File

/**
 * Builds the system prompts from the prompt files. Mirrors `PromptAssembly.swift`.
 *
 * Each template's placeholders are replaced by the trimmed section files they name. A section
 * file is only read when its placeholder is in the template, so a `polish.txt` edited before a
 * section existed keeps working unchanged: it simply has nothing to fill.
 */
class PromptAssembler(
    private val reader: PromptReading,
) {
    /**
     * The polish prompt: `polish.txt` with the shared rules, the channel guidelines and, only
     * when [learningSummary] is true, the learning summary section. When it is false the
     * placeholder is removed, so the prompt carries no summary instructions at all.
     *
     * @throws java.io.IOException when a needed file can't be read.
     */
    fun assemble(
        channel: Channel,
        learningSummary: Boolean,
    ): String =
        fill(
            PromptFile.Global,
            listOf(
                PromptFile.ALWAYS_PLACEHOLDER to PromptFile.Always,
                PromptFile.CHANNEL_PLACEHOLDER to PromptFile.ForChannel(channel),
                PromptFile.LEARNING_SUMMARY_PLACEHOLDER to
                    PromptFile.LearningSummary.takeIf { learningSummary },
            ),
        )

    /**
     * The refine prompt: `refine.txt` with the shared rules, the channel guidelines and the
     * [refinement] instruction.
     *
     * @throws java.io.IOException when a needed file can't be read.
     */
    fun assembleRefinement(
        refinement: Refinement,
        channel: Channel,
    ): String =
        fill(
            PromptFile.Refine,
            listOf(
                PromptFile.ALWAYS_PLACEHOLDER to PromptFile.Always,
                PromptFile.CHANNEL_PLACEHOLDER to PromptFile.ForChannel(channel),
                PromptFile.INSTRUCTION_PLACEHOLDER to PromptFile.ForRefinement(refinement),
            ),
        )

    /** Replaces each placeholder, in order, with its trimmed file; a null file removes it. */
    private fun fill(
        template: PromptFile,
        sections: List<Pair<String, PromptFile?>>,
    ): String {
        var text = reader.read(template).trim()
        for ((placeholder, file) in sections) {
            if (placeholder in text) {
                text = text.replace(placeholder, file?.let { reader.read(it).trim() }.orEmpty())
            }
        }
        return text.trim()
    }
}

/** Reads prompt files from a directory laid out like the bundled `Prompts` folder. */
class DirectoryPromptReader(
    private val directory: File,
) : PromptReading {
    override fun read(file: PromptFile): String =
        File(directory, file.relativePath).readText(Charsets.UTF_8)
}
