package local.writingassistant.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encodeToString
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING

/**
 * One processed request, as kept in the history. Mirrors `HistoryEntry` in `HistoryStore.swift`.
 * [channel] is stored by id; an id this version doesn't know decodes as [Channel.OTHER], so the
 * entry's texts are never lost to a renamed or removed channel.
 */
@Serializable
data class HistoryEntry(
    /** A random UUID string. */
    val id: String,
    /** Seconds since the epoch. */
    val epochSeconds: Long,
    @Serializable(with = ChannelIdSerializer::class) val channel: Channel,
    val input: String,
    val output: String,
    val learningSummary: LearningSummary?,
    val detectedLanguage: String,
    val wasTranslated: Boolean,
    val modelUsed: String,
    /**
     * The mode the request ran in, stored by id. Entries saved before modes existed have none;
     * they, and an id this version doesn't know, decode as [Mode.WORK], whose defaults match how
     * the app behaved before modes.
     */
    @Serializable(with = ModeIdSerializer::class) val mode: Mode = Mode.WORK,
)

/** Stores a [Mode] as its id; an unknown id decodes as [Mode.WORK]. */
internal object ModeIdSerializer : KSerializer<Mode> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("local.writingassistant.core.Mode", PrimitiveKind.STRING)

    override fun serialize(
        encoder: Encoder,
        value: Mode,
    ) = encoder.encodeString(value.id)

    override fun deserialize(decoder: Decoder): Mode =
        Mode.fromId(decoder.decodeString()) ?: Mode.WORK
}

/** Stores a [Channel] as its id; an unknown id decodes as [Channel.OTHER]. */
internal object ChannelIdSerializer : KSerializer<Channel> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("local.writingassistant.core.Channel", PrimitiveKind.STRING)

    override fun serialize(
        encoder: Encoder,
        value: Channel,
    ) = encoder.encodeString(value.id)

    override fun deserialize(decoder: Decoder): Channel =
        Channel.fromId(decoder.decodeString()) ?: Channel.OTHER
}

/**
 * A history file operation that failed; [message] names the file and what to do.
 *
 * @property fileKept True when [HistoryStore.load] left an unread file in place, so saving would
 *   overwrite history that may still be recoverable.
 */
class HistoryStoreException(
    message: String,
    cause: Throwable? = null,
    val fileKept: Boolean = false,
) : Exception(message, cause)

/** The most recent requests, stored as JSON in [file]. Mirrors `HistoryStore.swift`. */
class HistoryStore(
    val file: File,
    /** The most entries [save] keeps; must be positive. */
    val limit: Int = DEFAULT_LIMIT,
) {
    init {
        require(limit > 0) { "HistoryStore limit must be positive, got $limit" }
    }

    /** The damaged file is moved here, next to [file]. */
    val backupFile: File get() = File(file.absoluteFile.parentFile, BACKUP_NAME)

    /**
     * Reads the saved entries, newest first; empty when there is no file yet.
     *
     * @throws HistoryStoreException when the file can't be read, or can't be decoded (it is moved
     *   to [backupFile] first, so the next load is empty).
     */
    fun load(): List<HistoryEntry> {
        if (!file.exists()) {
            return emptyList()
        }
        val text =
            try {
                file.readText(Charsets.UTF_8)
            } catch (e: IOException) {
                throw HistoryStoreException(
                    "Couldn't read the history at ${file.path}: ${reason(e)}. Check that the " +
                        "file is readable, or move it away to start a new history.",
                    e,
                    fileKept = true,
                )
            }
        val entries =
            try {
                json.decodeFromString<List<HistoryEntry>>(text)
            } catch (e: SerializationException) {
                moveAside(e)
                throw HistoryStoreException(
                    "The history file was damaged, so history starts empty. The old file was " +
                        "moved to ${backupFile.path}; open it to recover past texts or delete it.",
                    e,
                )
            }
        return entries.sortedByDescending { it.epochSeconds }
    }

    /**
     * Writes [entries] atomically, sorted newest first and cut to [limit]; creates the folder.
     *
     * @throws HistoryStoreException naming the file.
     */
    fun save(entries: List<HistoryEntry>) {
        val kept = entries.sortedByDescending { it.epochSeconds }.take(limit)
        val target = file.absoluteFile.toPath()
        try {
            val directory = Files.createDirectories(target.parent)
            val temp = Files.createTempFile(directory, ".history", ".tmp")
            try {
                Files.writeString(temp, json.encodeToString(kept))
                Files.move(temp, target, ATOMIC_MOVE, REPLACE_EXISTING)
            } finally {
                Files.deleteIfExists(temp)
            }
        } catch (e: IOException) {
            throw HistoryStoreException(
                "Couldn't save the history to ${file.path}: ${reason(e)}. Check that the folder " +
                    "exists and is writable.",
                e,
            )
        }
    }

    private fun moveAside(decodeError: SerializationException) {
        try {
            Files.move(file.toPath(), backupFile.toPath(), REPLACE_EXISTING)
        } catch (e: IOException) {
            e.addSuppressed(decodeError)
            throw HistoryStoreException(
                "The history file at ${file.path} is damaged and couldn't be moved to " +
                    "${backupFile.path}: ${reason(e)}. Move or delete it to start a new history.",
                e,
                fileKept = true,
            )
        }
    }

    companion object {
        const val DEFAULT_LIMIT = 50
        private const val BACKUP_NAME = "history.corrupt.json"

        private val json =
            Json {
                ignoreUnknownKeys = true
                prettyPrint = true
                encodeDefaults = true
            }

        private fun reason(e: IOException): String =
            listOfNotNull(e.javaClass.simpleName, e.message).joinToString(": ")
    }
}
