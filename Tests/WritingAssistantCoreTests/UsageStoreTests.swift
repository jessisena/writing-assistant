import Foundation
import Testing
import WritingAssistantCore

/// A clock tests can move.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _date: Date

    init(_ date: Date) {
        _date = date
    }

    var date: Date {
        get { lock.withLock { _date } }
        set { lock.withLock { _date = newValue } }
    }
}

@Suite struct UsageStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "UsageStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private let clock = TestClock(Self.date("2026-10-29T12:00:00Z"))
    private let small = TokenUsage(input: 3, output: 40, cacheCreation: 100, cacheRead: 2_000)
    private let large = TokenUsage(input: 10, output: 500, cacheCreation: 0, cacheRead: 24_000)

    private var fileURL: URL { directory.appending(path: "nested/usage.json") }

    private var store: UsageStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let clock = clock
        return UsageStore(fileURL: fileURL, calendar: calendar, now: { clock.date })
    }

    private static func date(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    @Test func missingFileIsAnEmptyMonth() throws {
        #expect(try store.currentMonth() == .zero)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func recordsAddUpWithinAMonth() throws {
        try store.record(small)
        try store.record(large)

        #expect(try store.currentMonth() == MonthlyUsage(tokens: small + large, requests: 2))
        #expect(try store.currentMonth().tokens.total == 2_143 + 24_510)
    }

    @Test func aNewMonthStartsAtZeroAndKeepsTheOldOne() throws {
        try store.record(small)
        clock.date = Self.date("2026-11-01T00:30:00+01:00")

        #expect(try store.currentMonth() == .zero)
        try store.record(large)
        #expect(try store.currentMonth() == MonthlyUsage(tokens: large, requests: 1))

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved.contains("\"2026-10\""))
        #expect(saved.contains("\"2026-11\""))
    }

    @Test func monthFollowsTheCalendarTimeZone() throws {
        clock.date = Self.date("2026-10-31T23:30:00Z")

        try store.record(small)

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved.contains("\"2026-11\""))
    }

    @Test func damagedFileIsMovedAsideOnRead() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        #expect(throws: UsageStoreError.corrupted(backup: store.backupURL)) {
            try store.currentMonth()
        }
        #expect(try store.currentMonth() == .zero)
        #expect(try String(contentsOf: store.backupURL, encoding: .utf8) == "not json")
    }

    @Test func damagedFileIsMovedAsideAndCountingRestartsOnRecord() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"months\": 3}".utf8).write(to: fileURL)

        try store.record(small)

        #expect(try store.currentMonth() == MonthlyUsage(tokens: small, requests: 1))
        #expect(FileManager.default.fileExists(atPath: store.backupURL.path))
    }

    @Test func unwritableFolderFailsWithThePath() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appending(path: "nested"))

        #expect {
            try store.record(small)
        } throws: { error in
            guard case .writeFailed(let path, _) = error as? UsageStoreError else { return false }
            return path == fileURL.path
        }
    }

    @Test func concurrentRecordsAreAllCounted() async throws {
        let store = store
        let small = small
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { try? store.record(small) }
            }
        }

        #expect(try store.currentMonth().requests == 20)
        #expect(try store.currentMonth().tokens.output == 800)
    }

    @Test(arguments: [
        UsageStoreError.readFailed(path: "/u.json", reason: "Permission denied."),
        UsageStoreError.writeFailed(path: "/u.json", reason: "Permission denied."),
    ])
    func messagesHaveNoDoublePeriod(error: UsageStoreError) {
        #expect(error.errorDescription?.contains("..") == false)
    }
}
