package local.writingassistant.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.io.File

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
)

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

/** A history file operation that failed; [message] names the file and what to do. */
class HistoryStoreException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/** The most recent requests, stored as JSON in [file]. Mirrors `HistoryStore.swift`. */
class HistoryStore(
    val file: File,
    /** The most entries [save] keeps; must be positive. */
    val limit: Int = DEFAULT_LIMIT,
) {
    /** The damaged file is moved here, next to [file]. */
    val backupFile: File get() = TODO()

    /**
     * Reads the saved entries, newest first; empty when there is no file yet.
     *
     * @throws HistoryStoreException when the file can't be read, or can't be decoded (it is moved
     *   to [backupFile] first, so the next load is empty).
     */
    fun load(): List<HistoryEntry> = TODO()

    /**
     * Writes [entries] atomically, sorted newest first and cut to [limit]; creates the folder.
     *
     * @throws HistoryStoreException naming the file.
     */
    fun save(entries: List<HistoryEntry>): Unit = TODO()

    companion object {
        const val DEFAULT_LIMIT = 50
    }
}
