import AppKit
import WritingAssistantCore

extension AppModel {
    /// Appends the learning summary of a successful `process()` to the learning log.
    ///
    /// A result without a summary (translated text) or with an empty one writes nothing. A
    /// write failure goes to the error banner and leaves the result on screen.
    func appendToLearningLog(_ result: PolishResult, channel: Channel) {
        guard let summary = result.learningSummary, !summary.isEmpty else { return }
        do {
            try learningLog.append(summary, channel: channel, date: .now)
        } catch {
            showBanner(error)
        }
    }

    /// Opens the learning log in the default Markdown app, or explains in the error banner
    /// that it doesn't exist yet.
    ///
    /// - Parameter open: Opens the file. Defaults to `NSWorkspace`.
    func openLearningLog(using open: (URL) -> Void = { _ = NSWorkspace.shared.open($0) }) {
        let fileURL = learningLog.fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            showBanner(LearningLogMissing(path: fileURL.path))
            return
        }
        open(fileURL)
    }
}

/// Open Learning Log was chosen before any summary was written.
struct LearningLogMissing: LocalizedError {
    let path: String

    var errorDescription: String? {
        "There's no learning log yet. It starts with your first English text that has "
            + "corrections and will be saved at \(path)."
    }
}
