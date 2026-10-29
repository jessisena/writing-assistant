package local.writingassistant.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import local.writingassistant.core.Channel
import local.writingassistant.core.HistoryEntry
import local.writingassistant.core.HistoryStoreException
import local.writingassistant.core.LearningSummary
import local.writingassistant.core.PolishResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class HistoryRepositoryTest {
    private val file = mutableListOf<HistoryEntry>()
    private var saves = 0
    private var loads = 0
    private var failSaves = false
    private var loadError: HistoryStoreException? = null
    private var clock = 1_000L

    private fun repository(limit: Int = 50) =
        HistoryRepository(
            loadEntries = {
                loads++
                loadError?.let { throw it }
                file.toList()
            },
            saveEntries = {
                if (failSaves) throw IOException("disk full")
                saves++
                file.clear()
                file += it
            },
            limit = limit,
            ioDispatcher = Dispatchers.Unconfined,
            now = { clock++ },
        )

    private fun result(text: String) =
        PolishResult(
            polishedText = text,
            learningSummary = LearningSummary(emptyList(), "insight", emptyList()),
            detectedLanguage = "pt",
            wasTranslated = true,
            modelUsed = "model",
        )

    private suspend fun HistoryRepository.recordAll(vararg outputs: String) =
        outputs.map { record(result(it), "in $it", Channel.EMAIL) }

    @Test
    fun `a recorded polish keeps its texts and result`() =
        runTest {
            val history = repository()

            val entry = history.record(result("out"), "in", Channel.EMAIL)

            assertEquals(Channel.EMAIL, entry.channel)
            assertEquals("in", entry.input)
            assertEquals("out", entry.output)
            assertEquals("insight", entry.learningSummary?.grammarInsight)
            assertEquals("pt", entry.detectedLanguage)
            assertTrue(entry.wasTranslated)
            assertEquals("model", entry.modelUsed)
            assertEquals(1_000L, entry.epochSeconds)
            assertEquals(listOf(entry), history.entries.value)
            assertEquals(listOf(entry), file)
        }

    @Test
    fun `entries are newest first with distinct ids`() =
        runTest {
            val history = repository()

            val (first, second) = history.recordAll("a", "b")

            assertEquals(listOf(second, first), history.entries.value)
            assertTrue(first.id != second.id)
        }

    @Test
    fun `recording past the limit drops the oldest`() =
        runTest {
            val history = repository(limit = 2)

            history.recordAll("a", "b", "c")

            assertEquals(listOf("c", "b"), history.entries.value.map { it.output })
            assertEquals(listOf("c", "b"), file.map { it.output })
        }

    @Test
    fun `load reads the file once`() =
        runTest {
            repository().recordAll("saved")
            val history = repository()

            history.load()
            history.load()

            assertEquals(listOf("saved"), history.entries.value.map { it.output })
            assertEquals(1, loads)
        }

    @Test
    fun `delete removes only that entry`() =
        runTest {
            val history = repository()
            val (a, b) = history.recordAll("a", "b")

            history.delete(a.id)

            assertEquals(listOf(b), history.entries.value)
            assertEquals(listOf(b), file)
        }

    @Test
    fun `deleting an unknown id writes nothing`() =
        runTest {
            val history = repository()
            history.recordAll("a")

            history.delete("unknown")

            assertEquals(1, history.entries.value.size)
            assertEquals(1, saves)
        }

    @Test
    fun `clear removes every entry`() =
        runTest {
            val history = repository()
            history.recordAll("a", "b")

            history.clear()

            assertTrue(history.entries.value.isEmpty())
            assertTrue(file.isEmpty())
        }

    @Test
    fun `updateOutput replaces the output of that entry`() =
        runTest {
            val history = repository()
            val (a, b) = history.recordAll("a", "b")

            history.updateOutput(a.id, "edited")

            assertEquals(listOf(b, a.copy(output = "edited")), history.entries.value)
            assertEquals(history.entries.value, file)
        }

    @Test
    fun `updateOutput ignores blank, unchanged output and unknown ids`() =
        runTest {
            val history = repository()
            val (a) = history.recordAll("a")

            history.updateOutput(a.id, " \n ")
            history.updateOutput(a.id, "a")
            history.updateOutput("unknown", "edited")

            assertEquals(listOf(a), history.entries.value)
            assertEquals(1, saves)
        }

    @Test
    fun `a failed save keeps the change in memory and throws`() =
        runTest {
            val history = repository()
            failSaves = true

            val failure = runCatching { history.recordAll("a") }.exceptionOrNull()

            assertTrue(failure is IOException)
            assertEquals(listOf("a"), history.entries.value.map { it.output })
            assertTrue(file.isEmpty())
        }

    @Test
    fun `an unreadable file that was left in place is never overwritten`() =
        runTest {
            repository().recordAll("old")
            val error = HistoryStoreException("unreadable", fileKept = true)
            loadError = error
            val history = repository()
            saves = 0

            assertSame(error, runCatching { history.load() }.exceptionOrNull())
            history.recordAll("new")

            assertEquals(0, saves)
            assertEquals(listOf("old"), file.map { it.output })
            assertEquals(listOf("new"), history.entries.value.map { it.output })
        }

    @Test
    fun `a damaged file that was moved aside lets new history be saved`() =
        runTest {
            loadError = HistoryStoreException("damaged, moved aside")
            val history = repository()

            runCatching { history.load() }
            history.recordAll("new")

            assertEquals(listOf("new"), file.map { it.output })
        }
}
