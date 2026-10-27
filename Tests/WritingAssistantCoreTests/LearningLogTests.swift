import Foundation
import Testing

@testable import WritingAssistantCore

@Suite final class LearningLogTests {
    let root: URL
    let log: LearningLog

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "LearningLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        log = LearningLog(fileURL: root.appending(path: "nested/learning-log.md"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private let utc = TimeZone(identifier: "UTC")!
    private let date = Date(timeIntervalSince1970: 1_793_107_500)  // 2026-10-27 13:25:00 UTC

    private let summary = LearningSummary(
        corrections: [
            Correction(original: "I has went", corrected: "I went", why: "Past simple")
        ],
        grammarInsight: "Use the past simple for finished actions.",
        vocabulary: [
            VocabularyItem(term: "follow up", meaning: "check back", example: "I'll follow up.")
        ]
    )

    private func logText() throws -> String {
        try String(contentsOf: log.fileURL, encoding: .utf8)
    }

    @Test func entryFormatsEverySection() {
        let text = LearningLog.entry(for: summary, channel: .slack, date: date, timeZone: utc)

        #expect(
            text == """
                ## 2026-10-27 13:25:00 · Slack message

                ### Corrections
                - I has went → I went: Past simple

                ### Grammar insight
                Use the past simple for finished actions.

                ### Vocabulary
                - **follow up** — check back
                  _Example:_ I'll follow up.

                """)
    }

    @Test func entryUsesTheLocalTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let text = LearningLog.entry(for: summary, channel: .formal, date: date, timeZone: tokyo)

        #expect(text.hasPrefix("## 2026-10-27 22:25:00 · Formal document\n"))
    }

    @Test func entryLeavesOutEmptySectionsAndExamples() {
        let partial = LearningSummary(
            corrections: [],
            grammarInsight: "",
            vocabulary: [VocabularyItem(term: "gist", meaning: "main point", example: "")]
        )

        let text = LearningLog.entry(for: partial, channel: .other, date: date, timeZone: utc)

        #expect(!text.contains("### Corrections"))
        #expect(!text.contains("### Grammar insight"))
        #expect(!text.contains("_Example:_"))
        #expect(text.hasSuffix("### Vocabulary\n- **gist** — main point\n"))
    }

    @Test func entryFoldsLineBreaksInsideFields() {
        let multiline = LearningSummary(
            corrections: [Correction(original: "a\nb", corrected: "a b", why: "one\r\ntwo")],
            grammarInsight: "",
            vocabulary: []
        )

        let text = LearningLog.entry(for: multiline, channel: .slack, date: date, timeZone: utc)

        #expect(text.contains("- a b → a b: one two\n"))
    }

    @Test(arguments: [
        "# Use the past simple", "## Use the past simple", "- Use the past simple",
        "* Use the past simple", "+ Use the past simple", "> Use the past simple",
        "1. Use the past simple", "2) Use the past simple", "```Use the past simple",
        "    # Use the past simple",
    ])
    func grammarInsightStaysAParagraph(insight: String) throws {
        let entry = LearningLog.entry(
            for: LearningSummary(corrections: [], grammarInsight: insight, vocabulary: []),
            channel: .slack, date: date, timeZone: utc)

        let parsed = try AttributedString(markdown: entry)
        let insightRuns = parsed.runs.filter {
            String(parsed[$0.range].characters).contains("Use the past simple")
        }
        let kinds = insightRuns.flatMap { $0.presentationIntent?.components.map(\.kind) ?? [] }
        #expect(kinds == [.paragraph], "\(entry)")
        let text = insightRuns.map { String(parsed[$0.range].characters) }.joined()
        #expect(text == insight.trimmingCharacters(in: .whitespaces), "\(entry)")
    }

    @Test func appendingAnEmptySummaryWritesNothing() throws {
        let empty = LearningSummary(corrections: [], grammarInsight: "", vocabulary: [])

        try log.append(empty, channel: .slack, date: date)

        #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
    }

    @Test func appendCreatesTheFolderAndFile() throws {
        try log.append(summary, channel: .slack, date: date)

        #expect(try logText() == LearningLog.entry(for: summary, channel: .slack, date: date))
    }

    @Test func twoAppendsKeepBothEntriesInOrder() throws {
        let later = date.addingTimeInterval(3600)
        try log.append(summary, channel: .slack, date: date)
        try log.append(summary, channel: .formal, date: later)

        let first = LearningLog.entry(for: summary, channel: .slack, date: date)
        let second = LearningLog.entry(for: summary, channel: .formal, date: later)
        #expect(try logText() == first + "\n" + second)
    }

    @Test func appendKeepsExistingContent() throws {
        try FileManager.default.createDirectory(
            at: log.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# My notes\n".write(to: log.fileURL, atomically: true, encoding: .utf8)

        try log.append(summary, channel: .slack, date: date)

        #expect(try logText().hasPrefix("# My notes\n\n## "))
    }

    @Test func unwritableLocationThrowsAnErrorNamingThePath() throws {
        let blocker = root.appending(path: "not-a-folder")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "file".write(to: blocker, atomically: true, encoding: .utf8)
        let blocked = LearningLog(fileURL: blocker.appending(path: "learning-log.md"))

        let error = #expect(throws: LearningLogError.self) {
            try blocked.append(summary, channel: .slack, date: date)
        }

        #expect(error?.path == blocked.fileURL.path)
        #expect(error?.errorDescription?.contains(blocked.fileURL.path) == true)
    }

    @Test func standardLogLivesInApplicationSupport() {
        let path = LearningLog.standard().fileURL.path
        #expect(path.hasSuffix("/Library/Application Support/Writing Assistant/learning-log.md"))
    }
}
