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

    @Test
    fun everyBundledChannelAssemblesWithItsGuidelines() {
        Channel.entries.forEach { channel ->
            val guidelines = bundled.read(PromptFile.ForChannel(channel)).trim()

            val prompt = PromptAssembler(bundled).assemble(channel)

            assertTrue("${channel.id} guidelines missing", prompt.contains(guidelines))
            assertFalse("${channel.id} has a leftover placeholder", prompt.contains("{{"))
            assertFalse("${channel.id} has an em dash", prompt.contains("—"))
        }
    }

    @Test
    fun assembleTrimsBothFiles() {
        writePrompt(PromptFile.Global, "  Before\n${PromptFile.CHANNEL_PLACEHOLDER}\nAfter\n\n")
        writePrompt(PromptFile.ForChannel(Channel.SLACK), "\n  Guidelines  \n")

        val prompt = PromptAssembler(DirectoryPromptReader(temp.root)).assemble(Channel.SLACK)

        assertEquals("Before\nGuidelines\nAfter", prompt)
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

        assertThrows(IOException::class.java) { assembler.assemble(Channel.FORMAL) }
    }

    @Test
    fun missingGlobalFileThrowsIoException() {
        val assembler = PromptAssembler(DirectoryPromptReader(temp.root))

        assertThrows(IOException::class.java) { assembler.assemble(Channel.FORMAL) }
    }
}
