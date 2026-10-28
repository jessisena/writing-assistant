package local.writingassistant.core

import java.io.File

/** Builds the system prompt for a channel. Mirrors `PromptStore.assemble(for:)`. */
class PromptAssembler(
    private val reader: PromptReading,
) {
    /** `polish.txt` with the placeholder replaced by the channel file (both trimmed). */
    fun assemble(channel: Channel): String = TODO("core worker ($reader, $channel)")
}

/** Reads prompt files from a directory laid out like the bundled `Prompts` folder. */
class DirectoryPromptReader(
    private val directory: File,
) : PromptReading {
    override fun read(file: PromptFile): String = TODO("core worker ($directory, $file)")
}
