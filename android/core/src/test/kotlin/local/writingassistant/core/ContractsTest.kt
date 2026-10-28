package local.writingassistant.core

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class ContractsTest {
    @Test
    fun everyPromptFileExistsInTheSharedPromptsDirectory() {
        val dir = File(System.getProperty("prompts.dir"))
        val files =
            listOf(PromptFile.Global) +
                Channel.entries.map { PromptFile.ForChannel(it) } +
                Refinement.entries.map { PromptFile.ForRefinement(it) }

        val missing = files.filterNot { File(dir, it.relativePath).isFile }

        assertEquals(emptyList<PromptFile>(), missing)
    }

    @Test
    fun channelFromIdRoundTripsAndRejectsUnknownIds() {
        Channel.entries.forEach { assertEquals(it, Channel.fromId(it.id)) }
        assertEquals(null, Channel.fromId("nope"))
    }
}
