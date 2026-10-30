package local.writingassistant.core

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException

class PromptOverrideStoreTest {
    @get:Rule val temp = TemporaryFolder()

    private val defaults = StubPromptReader()
    private val slack = PromptFile.ForChannel(Channel.SLACK)

    private val directory: File get() = File(temp.root, "prompts")

    private fun store() = PromptOverrideStore(directory, defaults)

    @Test
    fun withoutAnEditEveryFileReadsTheDefault() {
        val store = store()

        PromptFile.all.forEach { file ->
            assertEquals(defaults.read(file), store.read(file))
            assertFalse(store.isCustomized(file))
        }
    }

    @Test
    fun savedEditWinsOverTheDefaultAndIsStoredWithTheBundledLayout() {
        val store = store()

        store.save(slack, "Keep it short. ✅")

        assertEquals("Keep it short. ✅", store.read(slack))
        assertEquals(defaults.read(slack), store.readDefault(slack))
        assertTrue(store.isCustomized(slack))
        assertEquals("Keep it short. ✅", File(directory, "channels/slack.txt").readText())
        assertEquals(listOf("slack.txt"), File(directory, "channels").list()?.toList())
    }

    @Test
    fun savingAgainReplacesTheEdit() {
        val store = store()
        store.save(slack, "first")

        store.save(slack, "second")

        assertEquals("second", store.read(slack))
    }

    @Test
    fun resetRestoresTheDefault() {
        val store = store()
        store.save(slack, "edited")

        store.reset(slack)

        assertEquals(defaults.read(slack), store.read(slack))
        assertFalse(store.isCustomized(slack))
    }

    @Test
    fun resetWithoutAnEditDoesNothing() {
        store().reset(PromptFile.Global)

        assertFalse(directory.exists())
    }

    @Test
    fun savingTheDefaultTextRemovesTheEdit() {
        val store = store()
        store.save(slack, "edited")

        store.save(slack, defaults.read(slack))

        assertFalse(store.isCustomized(slack))
        assertEquals(defaults.read(slack), store.read(slack))
    }

    @Test
    fun blankTextIsRejectedAndKeepsTheEdit() {
        val store = store()
        store.save(slack, "edited")

        listOf("", " \n\t ").forEach { text ->
            val error =
                assertThrows(PromptValidationException::class.java) { store.save(slack, text) }

            assertSame(PromptValidationException.Empty, error)
        }
        assertEquals("edited", store.read(slack))
    }

    @Test
    fun globalRulesWithoutThePlaceholderAreRejected() {
        val store = store()

        val error =
            assertThrows(PromptValidationException::class.java) {
                store.save(PromptFile.Global, "Rules with no channel slot")
            }

        assertEquals(
            PromptValidationException.MissingPlaceholder(PromptFile.CHANNEL_PLACEHOLDER),
            error,
        )
        assertTrue(error.message.contains("channel guidelines"))
        assertFalse(store.isCustomized(PromptFile.Global))
    }

    @Test
    fun refinePromptWithoutTheInstructionPlaceholderIsRejected() {
        val store = store()

        val error =
            assertThrows(PromptValidationException::class.java) {
                store.save(PromptFile.Refine, "Refine ${PromptFile.CHANNEL_PLACEHOLDER}")
            }

        assertEquals(
            PromptValidationException.MissingPlaceholder(PromptFile.INSTRUCTION_PLACEHOLDER),
            error,
        )
        assertTrue(error.message.contains("refinement instruction"))
        assertFalse(store.isCustomized(PromptFile.Refine))
    }

    @Test
    fun onlyTheTemplatesNeedTheirPlaceholder() {
        val store = store()

        store.save(PromptFile.Global, "NEW ${PromptFile.CHANNEL_PLACEHOLDER}")
        store.save(PromptFile.Refine, "NEW ${PromptFile.INSTRUCTION_PLACEHOLDER}")
        store.save(PromptFile.Always, "Be clear.")
        store.save(PromptFile.LearningSummary, "Explain the changes.")
        store.save(PromptFile.ForRefinement(Refinement.SHORTER), "Cut it in half.")

        assertTrue(store.isCustomized(PromptFile.Global))
        assertTrue(store.isCustomized(PromptFile.Refine))
        assertTrue(store.isCustomized(PromptFile.Always))
        assertTrue(store.isCustomized(PromptFile.LearningSummary))
        assertTrue(store.isCustomized(PromptFile.ForRefinement(Refinement.SHORTER)))
    }

    @Test
    fun writeFailureIsAnIOException() {
        temp.root.resolve("blocker").writeText("a file, not a folder")
        val store = PromptOverrideStore(File(temp.root, "blocker"), defaults)

        assertThrows(IOException::class.java) { store.save(slack, "edited") }
    }

    @Test
    fun polishUsesTheEditedChannelGuidelines() =
        runTest {
            val store = store()
            store.save(slack, "EDITED SLACK RULES")
            val client = replying(englishResponse)

            PolishService(client, store).polish("Hello there", Channel.SLACK)

            assertEquals(
                "SYSTEM EDITED SLACK RULES\nLEARNING RULES\n\n<draft>\nHello there\n</draft>",
                client.calls.single().prompt,
            )
        }
}
