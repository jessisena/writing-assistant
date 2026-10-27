import Foundation
import Testing

@testable import WritingAssistantCore

@Suite final class HistoryStoreTests {
    let root: URL
    let store: HistoryStore

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "HistoryStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = HistoryStore(fileURL: root.appending(path: "nested/history.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private let baseDate = Date(timeIntervalSince1970: 1_793_107_500)  // 2026-10-27T13:25:00Z

    private func entry(
        minutesLater minutes: Int = 0, channel: Channel = .slack, summary: LearningSummary? = nil
    ) -> HistoryEntry {
        HistoryEntry(
            date: baseDate.addingTimeInterval(TimeInterval(minutes * 60)),
            channel: channel,
            inputMarkdown: "i has **went** 👍 \(minutes)",
            outputMarkdown: "I **went** 👍 \(minutes)",
            learningSummary: summary,
            detectedLanguage: "en",
            wasTranslated: false,
            modelUsed: "sonnet"
        )
    }

    private func writeRaw(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: store.fileURL, atomically: true, encoding: .utf8)
    }

    @Test func missingFileLoadsAsEmpty() throws {
        #expect(try store.load().isEmpty)
    }

    @Test func entriesRoundTrip() throws {
        let summary = LearningSummary(
            corrections: [Correction(original: "has went", corrected: "went", why: "tense")],
            grammarInsight: "Past simple.",
            vocabulary: [VocabularyItem(term: "gist", meaning: "main point", example: "The gist")]
        )
        let entries = [
            entry(minutesLater: 1, channel: .formal, summary: summary),
            entry(minutesLater: 0, channel: .aiPrompt),
        ]

        try store.save(entries)

        #expect(try store.load() == entries)
    }

    @Test func fractionalSecondsDoNotBreakTheRoundTrip() throws {
        let saved = HistoryEntry(
            date: Date(timeIntervalSince1970: 1_793_107_500.75), channel: .slack,
            inputMarkdown: "a", outputMarkdown: "b", learningSummary: nil,
            detectedLanguage: "en", wasTranslated: true, modelUsed: "opus")

        try store.save([saved])

        #expect(try store.load() == [saved])
        #expect(saved.date == baseDate)
    }

    @Test func saveSortsNewestFirst() throws {
        let entries = [entry(minutesLater: 5), entry(minutesLater: 20), entry(minutesLater: 10)]

        try store.save(entries)

        #expect(try store.load().map(\.date) == [20, 10, 5].map { entry(minutesLater: $0).date })
    }

    @Test func saveKeepsOnlyTheNewestUpToTheLimit() throws {
        let entries = (0..<60).map { entry(minutesLater: $0) }

        try store.save(entries)

        let loaded = try store.load()
        #expect(loaded.count == 50)
        #expect(loaded.first == entries[59])
        #expect(loaded.last == entries[10])
    }

    @Test func customLimitIsRespected() throws {
        let small = HistoryStore(fileURL: store.fileURL, limit: 2)

        try small.save((0..<5).map { entry(minutesLater: $0) })

        #expect(try small.load().count == 2)
    }

    @Test func datesAreStoredAsStableISOStrings() throws {
        try store.save([entry()])
        let firstBytes = try Data(contentsOf: store.fileURL)

        try store.save(store.load())

        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"date\" : \"2026-10-27T13:25:00Z\""))
        #expect(try Data(contentsOf: store.fileURL) == firstBytes)
    }

    @Test func channelIsStoredAsItsRawValue() throws {
        try store.save([entry(channel: .slackInformal)])

        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"channel\" : \"slack_informal\""))
    }

    @Test func unknownChannelDecodesAsOtherAndKeepsTheTexts() throws {
        try store.save([entry()])
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        try writeRaw(text.replacingOccurrences(of: "\"slack\"", with: "\"carrier_pigeon\""))

        let loaded = try store.load()

        #expect(loaded.map(\.channel) == [.other])
        #expect(loaded.first?.outputMarkdown == entry().outputMarkdown)
    }

    @Test(arguments: ["{not json", "{\"entries\": []}", "[{\"id\": \"nope\"}]", ""])
    func corruptFileIsMovedAsideAndTheNextLoadIsEmpty(contents: String) throws {
        try writeRaw(contents)

        #expect(throws: HistoryStoreError.corrupted(backup: store.backupURL)) {
            try store.load()
        }

        let backup = try String(contentsOf: store.backupURL, encoding: .utf8)
        #expect(backup == contents)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(try store.load().isEmpty)
    }

    @Test func corruptFileReplacesAnOlderBackup() throws {
        try writeRaw("first broken file")
        #expect(throws: HistoryStoreError.self) { try store.load() }
        try writeRaw("second broken file")

        #expect(throws: HistoryStoreError.self) { try store.load() }

        #expect(try String(contentsOf: store.backupURL, encoding: .utf8) == "second broken file")
    }

    @Test func corruptedMessageNamesTheBackup() {
        let message = HistoryStoreError.corrupted(backup: store.backupURL).errorDescription
        #expect(message?.contains(store.backupURL.path) == true)
    }

    @Test func unreadableFileThrowsReadFailed() throws {
        try FileManager.default.createDirectory(
            at: store.fileURL, withIntermediateDirectories: true)

        let error = #expect(throws: HistoryStoreError.self) { try store.load() }

        guard case .readFailed(let path, _) = error else {
            Issue.record("expected readFailed, got \(String(describing: error))")
            return
        }
        #expect(path == store.fileURL.path)
    }

    @Test func unwritableLocationThrowsWriteFailedNamingThePath() throws {
        let blocker = root.appending(path: "not-a-folder")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "file".write(to: blocker, atomically: true, encoding: .utf8)
        let blocked = HistoryStore(fileURL: blocker.appending(path: "history.json"))

        let error = #expect(throws: HistoryStoreError.self) { try blocked.save([entry()]) }

        guard case .writeFailed(let path, _) = error else {
            Issue.record("expected writeFailed, got \(String(describing: error))")
            return
        }
        #expect(path == blocked.fileURL.path)
        #expect(error?.errorDescription?.contains(path) == true)
    }

    @Test func standardStoreLivesInApplicationSupport() {
        let standard = HistoryStore.standard()
        let suffix = "/Application Support/Writing Assistant/history.json"
        #expect(standard.fileURL.path.hasSuffix(suffix))
        #expect(standard.backupURL.lastPathComponent == "history.corrupt.json")
        #expect(standard.limit == 50)
    }
}
