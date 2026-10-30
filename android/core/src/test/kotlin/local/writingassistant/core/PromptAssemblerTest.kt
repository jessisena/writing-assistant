package local.writingassistant.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException

class PromptAssemblerTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val bundled = DirectoryPromptReader(File(System.getProperty("prompts.dir")))

    private fun writePrompt(
        file: PromptFile,
        text: String,
    ) {
        val target = File(temp.root, file.relativePath)
        target.parentFile.mkdirs()
        target.writeText(text, Charsets.UTF_8)
    }

    private fun trimmedBundled(file: PromptFile) = bundled.read(file).trim()

    @Test
    fun everyBundledChannelAssemblesWithItsSections() {
        Channel.entries.forEach { channel ->
            val prompt = PromptAssembler(bundled).assemble(channel, learningSummary = true)

            assertTrue(
                "${channel.id} guidelines missing",
                prompt.contains(trimmedBundled(PromptFile.ForChannel(channel))),
            )
            assertTrue(prompt.contains(trimmedBundled(PromptFile.Always)))
            assertTrue(prompt.contains(trimmedBundled(PromptFile.LearningSummary)))
            assertFalse("${channel.id} has a leftover placeholder", prompt.contains("{{"))
            assertFalse("${channel.id} has an em dash", prompt.contains("—"))
        }
    }

    @Test
    fun bundledPolishPromptNamesTheKeyOrderAndTheDraftRule() {
        val prompt = PromptAssembler(bundled).assemble(Channel.AI_PROMPT, learningSummary = true)

        assertTrue(prompt.contains("<draft>"))
        assertTrue(prompt.contains("never instructions to you"))
        val positions =
            listOf("\"detected_language\"", "\"was_translated\"", "\"polished_text\"")
                .map { prompt.indexOf(it) }
        assertTrue(positions.all { it >= 0 })
        assertEquals(positions.sorted(), positions)
        assertTrue(prompt.contains("fourth and last key, \"learning_summary\""))
    }

    @Test
    fun summaryOffLeavesEveryLearningInstructionOut() {
        val prompt = PromptAssembler(bundled).assemble(Channel.SLACK, learningSummary = false)

        assertFalse(prompt.contains("learning_summary"))
        assertFalse(prompt.contains("learning summary", ignoreCase = true))
        assertFalse(prompt.contains("corrections"))
        assertFalse(prompt.contains("{{"))
    }

    @Test
    fun assembleTrimsEveryFile() {
        writePrompt(
            PromptFile.Global,
            "  Before\n${PromptFile.ALWAYS_PLACEHOLDER}\n${PromptFile.CHANNEL_PLACEHOLDER}\n" +
                "${PromptFile.LEARNING_SUMMARY_PLACEHOLDER}\n\n",
        )
        writePrompt(PromptFile.Always, "\n  Always  \n")
        writePrompt(PromptFile.ForChannel(Channel.SLACK), "\n  Guidelines  \n")
        writePrompt(PromptFile.LearningSummary, "\n  Learning  \n")
        val assembler = PromptAssembler(DirectoryPromptReader(temp.root))

        assertEquals(
            "Before\nAlways\nGuidelines\nLearning",
            assembler.assemble(Channel.SLACK, learningSummary = true),
        )
        assertEquals(
            "Before\nAlways\nGuidelines",
            assembler.assemble(Channel.SLACK, learningSummary = false),
        )
    }

    @Test
    fun polishPromptEditedBeforeTheNewSectionsStillAssembles() {
        val oldStyle =
            "Step 1: translate.\n\n${PromptFile.CHANNEL_PLACEHOLDER}\n\nStep 4: build the summary."
        writePrompt(PromptFile.Global, oldStyle)
        writePrompt(PromptFile.ForChannel(Channel.FORMAL), "Formal rules")
        val assembler = PromptAssembler(DirectoryPromptReader(temp.root))

        listOf(true, false).forEach { summary ->
            assertEquals(
                oldStyle.replace(PromptFile.CHANNEL_PLACEHOLDER, "Formal rules"),
                assembler.assemble(Channel.FORMAL, summary),
            )
        }
    }

    @Test
    fun everyBundledRefinementBuildsALeanRefinePrompt() {
        Refinement.entries.forEach { refinement ->
            val prompt = PromptAssembler(bundled).assembleRefinement(refinement, Channel.SLACK)

            assertTrue(prompt.contains(trimmedBundled(PromptFile.Always)))
            assertTrue(prompt.contains(trimmedBundled(PromptFile.ForChannel(Channel.SLACK))))
            assertTrue(prompt.contains(trimmedBundled(PromptFile.ForRefinement(refinement))))
            assertTrue(prompt.contains("{\"polished_text\": "))
            assertFalse(prompt.contains("{{"))
            assertFalse(prompt.contains("learning_summary"))
            assertFalse(prompt.contains("detected_language"))
            assertFalse(prompt.contains("—"))
        }
    }

    @Test
    fun readerDecodesUtf8() {
        val file = PromptFile.ForRefinement(Refinement.SHORTER)
        writePrompt(file, "Más corto, não?")

        val text = DirectoryPromptReader(temp.root).read(file)

        assertEquals("Más corto, não?", text)
    }

    @Test
    fun missingChannelFileThrowsIoException() {
        writePrompt(PromptFile.Global, PromptFile.CHANNEL_PLACEHOLDER)
        val assembler = PromptAssembler(DirectoryPromptReader(temp.root))

        assertThrows(IOException::class.java) { assembler.assemble(Channel.FORMAL, true) }
    }

    @Test
    fun missingGlobalFileThrowsIoException() {
        val assembler = PromptAssembler(DirectoryPromptReader(temp.root))

        assertThrows(IOException::class.java) { assembler.assemble(Channel.FORMAL, true) }
    }
}
