import AppKit
import Foundation
import WritingAssistantCore

@testable import WritingAssistant

/// A new, empty folder under the temporary directory, so tests never touch Application Support.
func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "WritingAssistantTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

extension AppModel {
    /// A model whose files live in `directory` and that never touches the real pasteboard or
    /// waits.
    static func testing(
        polisher: any Polishing,
        directory: URL = makeTemporaryDirectory(),
        writeToPasteboard: @escaping @MainActor (ClipboardContent) -> Void = { _ in },
        sleep: @escaping @MainActor (Duration) async -> Void = { _ in },
        defaults: UserDefaults = TestDefaults.make()
    ) -> AppModel {
        AppModel(
            polisher: polisher,
            learningLog: LearningLog(fileURL: directory.appending(path: "learning-log.md")),
            historyStore: HistoryStore(fileURL: directory.appending(path: "history.json")),
            usageStore: UsageStore(fileURL: directory.appending(path: "usage.json")),
            writeToPasteboard: writeToPasteboard,
            sleep: sleep,
            defaults: defaults
        )
    }
}

/// Creates throwaway `UserDefaults` suites and removes every one when the test process exits,
/// so test runs leave no preference files behind.
enum TestDefaults {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var suiteNames: [String] = []
    private static let registerCleanup: Void = {
        atexit { TestDefaults.removeAll() }
    }()

    static func make() -> UserDefaults {
        _ = registerCleanup
        let name = "WritingAssistantTests-\(UUID().uuidString)"
        lock.withLock { suiteNames.append(name) }
        return UserDefaults(suiteName: name)!
    }

    private static func removeAll() {
        let names = lock.withLock { suiteNames }
        let preferences = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Preferences", directoryHint: .isDirectory)
        for name in names {
            UserDefaults().removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: preferences.appending(path: "\(name).plist"))
        }
    }
}
