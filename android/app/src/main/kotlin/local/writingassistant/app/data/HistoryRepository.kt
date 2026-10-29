package local.writingassistant.app.data

import kotlinx.coroutines.flow.StateFlow
import local.writingassistant.core.Channel
import local.writingassistant.core.HistoryEntry
import local.writingassistant.core.HistoryStore
import local.writingassistant.core.PolishResult

/**
 * The history shared by the composer and the History screen: [entries] in memory, newest first,
 * written to [store] after every change. File work runs on the IO dispatcher, one change at a
 * time. Mirrors `AppModel+History.swift`.
 *
 * Every function throws `HistoryStoreException` when the file can't be read or written; the
 * in-memory list keeps the change either way.
 */
class HistoryRepository(
    private val store: HistoryStore,
) {
    /** Empty until [load] finishes. */
    val entries: StateFlow<List<HistoryEntry>> get() = TODO()

    /** Reads the file once; later calls do nothing. */
    suspend fun load(): Unit = TODO()

    /** Adds a successful polish as the newest entry, keeping at most `store.limit`. */
    suspend fun record(
        result: PolishResult,
        input: String,
        channel: Channel,
    ): HistoryEntry = TODO()

    /** Replaces the output of entry [id]; does nothing for an unknown id or blank [output]. */
    suspend fun updateOutput(
        id: String,
        output: String,
    ): Unit = TODO()

    suspend fun delete(id: String): Unit = TODO()

    suspend fun clear(): Unit = TODO()
}
