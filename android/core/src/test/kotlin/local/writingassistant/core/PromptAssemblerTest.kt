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
            val prompt = PromptAssembler(bundled).assemble(channel, englishOptions())

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
        val prompt = PromptAssembler(bundled).assemble(Channel.AI_PROMPT, englishOptions())

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
        val prompt =
            PromptAssembler(
                bundled,
            ).assemble(Channel.SLACK, englishOptions(summary = false))

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
            assembler.assemble(Channel.SLACK, englishOptions()),
        )
        assertEquals(
            "Before\nAlways\nGuidelines",
            assembler.assemble(Channel.SLACK, englishOptions(summary = false)),
        )
    }

    @Test
    fun polishPromptEditedBeforeTheNewSectionsStillAssembles() {
        val oldStyle =
            "Step 1: translate.\n\n${PromptFile.CHANNEL_PLACEHOLDER}\n\nStep 4: build the summary."
        writePrompt(PromptFile.Global, oldStyle)
        writePrompt(PromptFile.ForChannel(Channel.FORMAL), "Formal rules")
        val assembler = PromptAssembler(DirectoryPromptReader(temp.root))

        listOf(englishOptions(), englishOptions(summary = false), sameAsInputOptions()).forEach {
            assertEquals(
                oldStyle.replace(PromptFile.CHANNEL_PLACEHOLDER, "Formal rules"),
                assembler.assemble(Channel.FORMAL, it),
            )
        }
    }

    @Test
    fun everyModeAndLanguageFillsItsSections() {
        Mode.entries.forEach { mode ->
            OutputLanguage.entries.forEach { language ->
                val options = PolishOptions(mode, language, includesLearningSummary = true)

                val prompt = PromptAssembler(bundled).assemble(Channel.PERSONAL_MESSAGE, options)

                assertTrue(prompt.contains(trimmedBundled(PromptFile.ForMode(mode))))
                assertTrue(prompt.contains(trimmedBundled(PromptFile.ForLanguage(language))))
                assertFalse(prompt.contains(trimmedBundled(PromptFile.ForMode(mode.toggled))))
                assertFalse(prompt.contains("{{"))
            }
        }
    }

    @Test
    fun sameAsInputPromptNeverAsksForATranslation() {
        val prompt =
            PromptAssembler(
                bundled,
            ).assemble(Channel.PERSONAL_MESSAGE, sameAsInputOptions())

        assertFalse(prompt.contains("translate it to English"))
        assertFalse(prompt.contains("always in English"))
        assertTrue(prompt.contains("Never translate"))
        assertTrue(prompt.contains("If the draft isn't in English, set learning_summary to null"))
    }

    @Test
    fun wave2PolishPromptWithoutModeOrLanguageSlotsDoesNotReadThoseFiles() {
        val wave2 =
            "Rules\n${PromptFile.ALWAYS_PLACEHOLDER}\nTranslate to English.\n" +
                "${PromptFile.CHANNEL_PLACEHOLDER}\n${PromptFile.LEARNING_SUMMARY_PLACEHOLDER}"
        writePrompt(PromptFile.Global, wave2)
        writePrompt(PromptFile.Always, "Always")
        writePrompt(PromptFile.ForChannel(Channel.SLACK), "Slack rules")
        val assembler = PromptAssembler(DirectoryPromptReader(temp.root))

        assertEquals(
            "Rules\nAlways\nTranslate to English.\nSlack rules",
            assembler.assemble(Channel.SLACK, sameAsInputOptions(summary = false)),
        )
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

        assertThrows(
            IOException::class.java,
        ) { assembler.assemble(Channel.FORMAL, englishOptions()) }
    }

    @Test
    fun missingGlobalFileThrowsIoException() {
        val assembler = PromptAssembler(DirectoryPromptReader(temp.root))

        assertThrows(
            IOException::class.java,
        ) { assembler.assemble(Channel.FORMAL, englishOptions()) }
    }
}
