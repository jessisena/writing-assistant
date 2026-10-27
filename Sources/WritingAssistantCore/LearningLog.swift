import Foundation

/// A learning log write that failed, with the file it was writing.
public struct LearningLogError: LocalizedError, Sendable {
    public let path: String
    public let reason: String

    public var errorDescription: String? {
        "Couldn't write the learning log at \(path): \(reason). "
            + "Check that the folder exists and is writable."
    }
}

/// A Markdown file that collects every learning summary the app shows.
public struct LearningLog: Sendable {
    /// `~/Library/Application Support/Writing Assistant/learning-log.md`.
    public static func standard() -> LearningLog {
        let fileURL = URL.applicationSupportDirectory
            .appending(path: "Writing Assistant", directoryHint: .isDirectory)
            .appending(path: "learning-log.md", directoryHint: .notDirectory)
        return LearningLog(fileURL: fileURL)
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Formats one log entry as Markdown.
    ///
    /// The heading holds the local date and time (ISO 8601, `yyyy-MM-dd HH:mm:ss`) and the
    /// channel name. Corrections, the grammar insight and vocabulary each get a section, which is
    /// left out when it has no content. Line breaks inside a field are folded into spaces so
    /// every list item stays on one line, and the grammar insight is escaped so it always reads
    /// as a paragraph, never as a heading, list or quote.
    ///
    /// - Parameters:
    ///   - summary: The learning summary to format.
    ///   - channel: The channel the text was written for.
    ///   - date: When the text was processed.
    /// - Returns: The entry, ending with a newline.
    public static func entry(for summary: LearningSummary, channel: Channel, date: Date) -> String {
        entry(for: summary, channel: channel, date: date, timeZone: .current)
    }

    static func entry(
        for summary: LearningSummary, channel: Channel, date: Date, timeZone: TimeZone
    ) -> String {
        var sections = ["## \(heading(date, timeZone: timeZone)) · \(channel.displayName)"]
        if !summary.corrections.isEmpty {
            let items = summary.corrections.map {
                "- \(oneLine($0.original)) → \(oneLine($0.corrected)): \(oneLine($0.why))"
            }
            sections.append((["### Corrections"] + items).joined(separator: "\n"))
        }
        if !summary.grammarInsight.isEmpty {
            sections.append("### Grammar insight\n\(paragraph(summary.grammarInsight))")
        }
        if !summary.vocabulary.isEmpty {
            let items = summary.vocabulary.map(vocabularyItem)
            sections.append((["### Vocabulary"] + items).joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    /// Appends the entry for `summary` to the log file.
    ///
    /// Creates the parent folder and the file when they don't exist. Entries are separated by a
    /// blank line. The whole file is rewritten atomically, so a failed write never leaves a
    /// half-written entry. An empty summary (`LearningSummary.isEmpty`) writes nothing, so the
    /// log only holds entries with something to learn.
    ///
    /// Call from one actor: appending reads the file and writes it back, so concurrent appends
    /// to the same file can lose an entry.
    ///
    /// - Throws: `LearningLogError` naming the file when the folder or file can't be written.
    public func append(_ summary: LearningSummary, channel: Channel, date: Date) throws {
        guard !summary.isEmpty else { return }
        let text = Self.entry(for: summary, channel: channel, date: date)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(text)
        } catch {
            throw LearningLogError(path: fileURL.path, reason: error.localizedDescription)
        }
    }

    private func write(_ text: String) throws {
        var contents = Data()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            contents = try Data(contentsOf: fileURL)
        }
        if !contents.isEmpty {
            contents.append(Data("\n".utf8))
        }
        contents.append(Data(text.utf8))
        try contents.write(to: fileURL, options: .atomic)
    }

    private static func heading(_ date: Date, timeZone: TimeZone) -> String {
        let style = Date.ISO8601FormatStyle(
            dateSeparator: .dash, dateTimeSeparator: .space, timeSeparator: .colon,
            timeZone: timeZone
        )
        .year().month().day().time(includingFractionalSeconds: false)
        return date.formatted(style)
    }

    private static func vocabularyItem(_ item: VocabularyItem) -> String {
        let line = "- **\(oneLine(item.term))** — \(oneLine(item.meaning))"
        guard !item.example.isEmpty else { return line }
        return line + "\n  _Example:_ \(oneLine(item.example))"
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// Folds `text` onto one line that Markdown reads as a plain paragraph: leading spaces are
    /// dropped and a leading heading, list, quote or code fence marker is backslash-escaped.
    private static func paragraph(_ text: String) -> String {
        let line = String(oneLine(text).drop(while: \.isWhitespace))
        guard let first = line.first else {
            return line
        }
        if "#-+*>`~<".contains(first) {
            return "\\" + line
        }
        let digits = String(line.prefix(while: { $0.isASCII && $0.isNumber }))
        let rest = String(line.dropFirst(digits.count))
        if !digits.isEmpty, let marker = rest.first, ".)".contains(marker) {
            return digits + "\\" + rest
        }
        return line
    }
}
