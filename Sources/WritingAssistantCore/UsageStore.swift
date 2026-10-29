import Foundation
import os

/// A usage file operation that failed.
public enum UsageStoreError: LocalizedError, Equatable, Sendable {
    /// The file couldn't be decoded. It was moved to `backup` and counting starts again.
    case corrupted(backup: URL)
    case readFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .corrupted(let backup):
            "The token usage file was damaged, so this month's count starts again. The old file "
                + "was moved to \(backup.path)."
        case .readFailed(let path, let reason):
            "Couldn't read the token usage at \(path): \(reason.withoutTrailingPeriod). "
                + "Check that the file is readable, or move it away to start counting again."
        case .writeFailed(let path, let reason):
            "Couldn't save the token usage to \(path): \(reason.withoutTrailingPeriod). "
                + "Check that the folder exists and is writable."
        }
    }
}

/// Token totals per calendar month, stored as JSON keyed by "yyyy-MM".
public struct UsageStore: UsageRecording {
    /// `~/Library/Application Support/Writing Assistant/usage.json`.
    public static func standard() -> UsageStore {
        let fileURL = URL.applicationSupportDirectory
            .appending(path: "Writing Assistant", directoryHint: .isDirectory)
            .appending(path: "usage.json", directoryHint: .notDirectory)
        return UsageStore(fileURL: fileURL)
    }

    private struct File: Codable {
        var months: [String: MonthlyUsage]
    }

    public static var gregorianInUserTimeZone: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    /// Serializes read-modify-write cycles across every copy of a store.
    private static let lock = OSAllocatedUnfairLock()

    public let fileURL: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// The damaged file is moved here, next to `fileURL`.
    public var backupURL: URL {
        fileURL.deletingLastPathComponent().appending(path: "usage.corrupt.json")
    }

    /// Creates a store for `fileURL`.
    ///
    /// - Parameters:
    ///   - fileURL: The JSON file. It and its folder are created on the first record.
    ///   - calendar: Decides where a month starts. Defaults to the Gregorian calendar in the user's
    ///     time zone, so keys stay "yyyy-MM" whatever calendar the user picked in System Settings.
    ///   - now: The current date. Defaults to the system clock.
    public init(
        fileURL: URL,
        calendar: Calendar = UsageStore.gregorianInUserTimeZone,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
    }

    /// Adds `usage`, as one request, to the current month.
    ///
    /// A damaged file is moved to `backupURL` and counting starts again from `usage`.
    ///
    /// - Throws: `UsageStoreError.readFailed` or `.writeFailed` naming the file.
    public func record(_ usage: TokenUsage) throws {
        try Self.lock.withLock {
            var file: File
            do {
                file = try read()
            } catch UsageStoreError.corrupted {
                file = File(months: [:])
            }
            let key = monthKey(for: now())
            var month = file.months[key] ?? .zero
            month.tokens = month.tokens + usage
            month.requests += 1
            file.months[key] = month
            try write(file)
        }
    }

    /// The current month's totals, or zero when nothing was recorded this month.
    ///
    /// - Throws: `UsageStoreError.corrupted(backup:)` when the file can't be decoded (it is moved
    ///   to `backupURL` first, so the next call returns zero), or `.readFailed`.
    public func currentMonth() throws -> MonthlyUsage {
        try Self.lock.withLock {
            try read().months[monthKey(for: now())] ?? .zero
        }
    }

    private func monthKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func read() throws -> File {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return File(months: [:])
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw UsageStoreError.readFailed(path: fileURL.path, reason: error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(File.self, from: data)
        } catch {
            try moveAside()
            throw UsageStoreError.corrupted(backup: backupURL)
        }
    }

    private func write(_ file: File) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw UsageStoreError.writeFailed(
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
            throw UsageStoreError.writeFailed(
                path: backupURL.path,
                reason: "the usage file is damaged and couldn't be moved aside "
                    + "(\(error.localizedDescription))")
        }
    }
}
