package local.writingassistant.core

import java.io.File

/** Builds the system prompt for a channel. Mirrors `PromptStore.assemble(for:)`. */
class PromptAssembler(
    private val reader: PromptReading,
) {
    /**
     * Returns `polish.txt` with the placeholder replaced by the channel file (both trimmed).
     *
     * @throws java.io.IOException when either file can't be read.
     */
    fun assemble(channel: Channel): String {
        val global = reader.read(PromptFile.Global).trim()
        val guidelines = reader.read(PromptFile.ForChannel(channel)).trim()
        return global.replace(PromptFile.CHANNEL_PLACEHOLDER, guidelines)
    }
}

/** Reads prompt files from a directory laid out like the bundled `Prompts` folder. */
class DirectoryPromptReader(
    private val directory: File,
) : PromptReading {
    override fun read(file: PromptFile): String =
        File(directory, file.relativePath).readText(Charsets.UTF_8)
}
