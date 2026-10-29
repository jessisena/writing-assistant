package local.writingassistant.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class HistoryStoreTest {
    @get:Rule val temp = TemporaryFolder()

    private val historyFile: File get() = File(temp.root, "data/history.json")

    private fun entry(
        epochSeconds: Long,
        channel: Channel = Channel.SLACK,
        summary: LearningSummary? = null,
    ) = HistoryEntry(
        id = "id-$epochSeconds",
        epochSeconds = epochSeconds,
        channel = channel,
        input = "input $epochSeconds",
        output = "output $epochSeconds",
        learningSummary = summary,
        detectedLanguage = "English",
        wasTranslated = false,
        modelUsed = "model",
    )

    private val summary =
        LearningSummary(
            corrections = listOf(Correction("pls", "please", "Spell out polite words.")),
            grammarInsight = "Avoid abbreviations.",
            vocabulary = listOf(VocabularyItem("by end of day", "before the day ends", "Do it.")),
        )

    @Test
    fun savedEntriesLoadBackNewestFirst() {
        val store = HistoryStore(historyFile)
        val entries =
            listOf(entry(1, summary = summary), entry(3, Channel.EMAIL), entry(2, Channel.OTHER))

        store.save(entries)

        assertEquals(listOf(entries[1], entries[2], entries[0]), store.load())
    }

    @Test
    fun saveKeepsOnlyTheNewestUpToTheLimit() {
        val store = HistoryStore(historyFile, limit = 2)

        store.save(listOf(entry(10), entry(30), entry(20), entry(5)))

        assertEquals(listOf(30L, 20L), store.load().map { it.epochSeconds })
    }

    @Test
    fun nonPositiveLimitIsRejected() {
        listOf(0, -1).forEach { limit ->
            assertThrows(IllegalArgumentException::class.java) { HistoryStore(historyFile, limit) }
        }
    }

    @Test
    fun missingFileLoadsEmpty() {
        assertEquals(emptyList<HistoryEntry>(), HistoryStore(historyFile).load())
    }

    @Test
    fun emptyListRoundTrips() {
        val store = HistoryStore(historyFile)

        store.save(emptyList())

        assertEquals(emptyList<HistoryEntry>(), store.load())
    }

    @Test
    fun saveReplacesThePreviousFileAndLeavesNoTempFiles() {
        val store = HistoryStore(historyFile)
        store.save(listOf(entry(1)))

        store.save(listOf(entry(2)))

        assertEquals(listOf(entry(2)), store.load())
        assertEquals(listOf("history.json"), historyFile.parentFile.list()?.toList())
    }

    @Test
    fun corruptFileIsMovedToTheBackupAndTheNextLoadIsEmpty() {
        val store = HistoryStore(historyFile)
        historyFile.parentFile.mkdirs()
        store.backupFile.writeText("older backup")
        historyFile.writeText("{ not json")

        val error = assertThrows(HistoryStoreException::class.java) { store.load() }

        assertEquals(File(historyFile.parentFile, "history.corrupt.json"), store.backupFile)
        assertTrue(error.message!!.contains(store.backupFile.path))
        assertTrue(error.message!!.contains("history starts empty"))
        assertEquals("{ not json", store.backupFile.readText())
        assertFalse(historyFile.exists())
        assertEquals(emptyList<HistoryEntry>(), store.load())
    }

    @Test
    fun wrongShapeIsTreatedAsCorrupt() {
        val store = HistoryStore(historyFile)
        historyFile.parentFile.mkdirs()
        historyFile.writeText("""[{"id": "x"}]""")

        assertThrows(HistoryStoreException::class.java) { store.load() }
        assertTrue(store.backupFile.exists())
    }

    @Test
    fun unknownChannelIdLoadsAsOtherAndUnknownKeysAreIgnored() {
        historyFile.parentFile.mkdirs()
        historyFile.writeText(
            """
            [{"id": "a", "epochSeconds": 7, "channel": "retired_channel", "input": "in",
              "output": "out", "learningSummary": null, "detectedLanguage": "English",
              "wasTranslated": false, "modelUsed": "m", "addedLater": true}]
            """.trimIndent(),
        )

        val loaded = HistoryStore(historyFile).load().single()

        assertEquals(Channel.OTHER, loaded.channel)
        assertEquals("out", loaded.output)
    }

    @Test
    fun unreadableFileIsAReadFailureNamingThePath() {
        historyFile.mkdirs()

        val error =
            assertThrows(HistoryStoreException::class.java) { HistoryStore(historyFile).load() }

        assertTrue(error.message!!.contains("Couldn't read the history at ${historyFile.path}"))
    }

    @Test
    fun writeFailureNamesTheFile() {
        val blocker = File(temp.root, "blocker").apply { writeText("a file, not a folder") }
        val file = File(blocker, "history.json")

        val error =
            assertThrows(HistoryStoreException::class.java) {
                HistoryStore(file).save(listOf(entry(1)))
            }

        assertTrue(error.message!!.contains("Couldn't save the history to ${file.path}"))
    }
}
