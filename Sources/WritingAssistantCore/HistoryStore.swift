import Foundation

/// One processed request, as kept in the history.
public struct HistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    /// Truncated to whole seconds so an entry is equal to itself after a save and load.
    public let date: Date
    /// Stored as `Channel.rawValue`. A value this version doesn't know (a channel that was
    /// renamed or removed) decodes as `.other`, so the entry's texts are never lost to it.
    public var channel: Channel
    public var inputMarkdown: String
    public var outputMarkdown: String
    public var learningSummary: LearningSummary?
    public var detectedLanguage: String
    public var wasTranslated: Bool
    public var modelUsed: String

    enum CodingKeys: String, CodingKey {
        case id, date, channel, inputMarkdown, outputMarkdown, learningSummary
        case detectedLanguage, wasTranslated, modelUsed
    }

    public init(
        id: UUID = UUID(),
        date: Date,
        channel: Channel,
        inputMarkdown: String,
        outputMarkdown: String,
        learningSummary: LearningSummary?,
        detectedLanguage: String,
        wasTranslated: Bool,
        modelUsed: String
    ) {
        self.id = id
        self.date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        self.channel = channel
        self.inputMarkdown = inputMarkdown
        self.outputMarkdown = outputMarkdown
        self.learningSummary = learningSummary
        self.detectedLanguage = detectedLanguage
        self.wasTranslated = wasTranslated
        self.modelUsed = modelUsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawChannel = try container.decode(String.self, forKey: .channel)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            date: try container.decode(Date.self, forKey: .date),
            channel: Channel(rawValue: rawChannel) ?? .other,
            inputMarkdown: try container.decode(String.self, forKey: .inputMarkdown),
            outputMarkdown: try container.decode(String.self, forKey: .outputMarkdown),
            learningSummary: try container.decodeIfPresent(
                LearningSummary.self, forKey: .learningSummary),
            detectedLanguage: try container.decode(String.self, forKey: .detectedLanguage),
            wasTranslated: try container.decode(Bool.self, forKey: .wasTranslated),
            modelUsed: try container.decode(String.self, forKey: .modelUsed)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(channel.rawValue, forKey: .channel)
        try container.encode(inputMarkdown, forKey: .inputMarkdown)
        try container.encode(outputMarkdown, forKey: .outputMarkdown)
        try container.encodeIfPresent(learningSummary, forKey: .learningSummary)
        try container.encode(detectedLanguage, forKey: .detectedLanguage)
        try container.encode(wasTranslated, forKey: .wasTranslated)
        try container.encode(modelUsed, forKey: .modelUsed)
    }
}

/// A history file operation that failed.
public enum HistoryStoreError: LocalizedError, Equatable, Sendable {
    /// The file couldn't be decoded. It was moved to `backup` and the history starts empty.
    case corrupted(backup: URL)
    case readFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .corrupted(let backup):
            "The history file was damaged, so history starts empty. The old file was moved to "
                + "\(backup.path); open it to recover past texts or delete it."
        case .readFailed(let path, let reason):
            "Couldn't read the history at \(path): \(reason.withoutTrailingPeriod). "
                + "Check that the file is readable, or move it away to start a new history."
        case .writeFailed(let path, let reason):
            "Couldn't save the history to \(path): \(reason.withoutTrailingPeriod). "
                + "Check that the folder exists and is writable."
        }
    }
}

/// The most recent requests, stored as JSON with ISO 8601 dates.
public struct HistoryStore: Sendable {
    /// `~/Library/Application Support/Writing Assistant/history.json`.
    public static func standard() -> HistoryStore {
        let fileURL = URL.applicationSupportDirectory
            .appending(path: "Writing Assistant", directoryHint: .isDirectory)
            .appending(path: "history.json", directoryHint: .notDirectory)
        return HistoryStore(fileURL: fileURL)
    }

    public let fileURL: URL
    /// The most entries `save` keeps.
    public let limit: Int

    /// The corrupt file is moved here, next to `fileURL`.
    public var backupURL: URL {
        fileURL.deletingLastPathComponent().appending(path: "history.corrupt.json")
    }

    /// Creates a store for `fileURL` that keeps at most `limit` entries (must be positive).
    public init(fileURL: URL, limit: Int = 50) {
        precondition(limit > 0, "HistoryStore limit must be positive, got \(limit)")
        self.fileURL = fileURL
        self.limit = limit
    }

    /// Reads the saved entries, newest first.
    ///
    /// - Returns: The entries, or `[]` when there is no history file yet.
    /// - Throws: `HistoryStoreError.corrupted(backup:)` when the file can't be decoded; the file
    ///   is moved to `backupURL` first (replacing an older backup), so the next load is empty.
    ///   `.readFailed` when the file can't be read, `.writeFailed` when it can't be moved aside.
    public func load() throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw HistoryStoreError.readFailed(
                path: fileURL.path, reason: error.localizedDescription)
        }
        do {
            return try Self.decoder.decode([HistoryEntry].self, from: data)
        } catch {
            try moveAside()
            throw HistoryStoreError.corrupted(backup: backupURL)
        }
    }

    /// Writes `entries` atomically, sorted newest first and cut to `limit`.
    ///
    /// Creates the parent folder when it doesn't exist.
    ///
    /// - Throws: `HistoryStoreError.writeFailed` naming the file.
    public func save(_ entries: [HistoryEntry]) throws {
        let kept = Array(entries.sorted { $0.date > $1.date }.prefix(limit))
        do {
            let data = try Self.encoder.encode(kept)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw HistoryStoreError.writeFailed(
                path: fileURL.path, reason: error.localizedDescription)
        }
    }

    private func moveAside() throws {
        let manager = FileManager.default
        do {
            if manager.fileExists(atPath: backupURL.path) {
                try manager.removeItem(at: backupURL)
            }
            try manager.moveItem(at: fileURL, to: backupURL)
        } catch {
            throw HistoryStoreError.writeFailed(
                path: backupURL.path,
                reason: "the history file is damaged and couldn't be moved aside "
                    + "(\(error.localizedDescription))")
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
