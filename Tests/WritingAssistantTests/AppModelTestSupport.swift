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
        sleep: @escaping @MainActor (Duration) async -> Void = { _ in }
    ) -> AppModel {
        AppModel(
            polisher: polisher,
            learningLog: LearningLog(fileURL: directory.appending(path: "learning-log.md")),
            historyStore: HistoryStore(fileURL: directory.appending(path: "history.json")),
            writeToPasteboard: writeToPasteboard,
            sleep: sleep
        )
    }
}
