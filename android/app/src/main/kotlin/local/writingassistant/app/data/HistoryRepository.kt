package local.writingassistant.app.data

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import local.writingassistant.core.Channel
import local.writingassistant.core.HistoryEntry
import local.writingassistant.core.HistoryStore
import local.writingassistant.core.PolishResult
import java.util.UUID

/**
 * The history shared by the composer and the History screen: [entries] in memory, newest first,
 * written to the file after every change. File work runs on the IO dispatcher, one change at a
 * time. Mirrors `AppModel+History.swift`.
 *
 * Every function throws `HistoryStoreException` when the file can't be read or written; the
 * in-memory list keeps the change either way.
 *
 * The internal constructor replaces the file with [loadEntries] and [saveEntries] (and lets tests
 * pick the dispatcher and clock), so tests can keep the history in memory or make saving fail.
 */
class HistoryRepository internal constructor(
    private val loadEntries: () -> List<HistoryEntry>,
    private val saveEntries: (List<HistoryEntry>) -> Unit,
    /** The most entries kept; older ones are dropped by [record]. */
    private val limit: Int = HistoryStore.DEFAULT_LIMIT,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    /** Seconds since the epoch. */
    private val now: () -> Long = { System.currentTimeMillis() / MILLIS_PER_SECOND },
) {
    constructor(store: HistoryStore) : this(store::load, store::save, store.limit)

    private val mutableEntries = MutableStateFlow(emptyList<HistoryEntry>())
    private val mutex = Mutex()
    private var loaded = false

    /** Empty until [load] finishes. */
    val entries: StateFlow<List<HistoryEntry>> = mutableEntries.asStateFlow()

    /** Reads the file once; later calls do nothing, even when the first read failed. */
    suspend fun load() {
        mutex.withLock {
            if (loaded) return
            loaded = true
            mutableEntries.value = withContext(ioDispatcher) { loadEntries() }
        }
    }

    /**
     * Adds a successful polish as the newest entry, keeping at most `limit`. When saving fails
     * the entry is still the newest one in [entries].
     */
    suspend fun record(
        result: PolishResult,
        input: String,
        channel: Channel,
    ): HistoryEntry {
        val entry =
            HistoryEntry(
                id = UUID.randomUUID().toString(),
                epochSeconds = now(),
                channel = channel,
                input = input,
                output = result.polishedText,
                learningSummary = result.learningSummary,
                detectedLanguage = result.detectedLanguage,
                wasTranslated = result.wasTranslated,
                modelUsed = result.modelUsed,
            )
        change { (listOf(entry) + it).take(limit) }
        return entry
    }

    /**
     * Replaces the output of entry [id]; does nothing for an unknown id, blank [output] or an
     * unchanged output.
     */
    suspend fun updateOutput(
        id: String,
        output: String,
    ) {
        if (output.isBlank()) return
        change { current ->
            val index = current.indexOfFirst { it.id == id }
            if (index < 0 || current[index].output == output) return@change null
            current.toMutableList().apply { set(index, current[index].copy(output = output)) }
        }
    }

    suspend fun delete(id: String) {
        change { current -> current.filterNot { it.id == id }.takeIf { it.size != current.size } }
    }

    suspend fun clear() {
        change { emptyList() }
    }

    /**
     * Applies [transform] to the list and saves the result; a null result means nothing changed
     * and nothing is written. The new list is kept in memory before saving, so a failed save
     * still shows the change.
     */
    private suspend fun change(transform: (List<HistoryEntry>) -> List<HistoryEntry>?) {
        mutex.withLock {
            val next = transform(mutableEntries.value) ?: return
            mutableEntries.value = next
            withContext(ioDispatcher) { saveEntries(next) }
        }
    }

    private companion object {
        const val MILLIS_PER_SECOND = 1000L
    }
}
