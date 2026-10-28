import Foundation
import WritingAssistantCore

extension AppModel {
    /// True when there is a polished result with non-blank output and no request is running.
    var canRefine: Bool {
        !isLoading && result != nil && !outputMarkdown.isEmpty
    }

    /// Asks Claude to apply `refinement` to the current, possibly edited, output.
    ///
    /// The output is sent as Markdown with the current history entry's channel (the one it was
    /// polished for), or the selected channel when there is no current entry, and is replaced by
    /// the answer. The result keeps its learning summary and language, since a summary of the
    /// model's own text means nothing. The refined output is saved to the current history entry;
    /// the learning log is left alone. Runs in `requests`, so `cancel()` stops it. Ignored
    /// unless `canRefine`.
    func refine(_ refinement: Refinement) {
        guard canRefine else { return }
        let text = outputMarkdown
        let channel = history.first { $0.id == currentHistoryID }?.channel ?? channel
        guard let generation = beginRequest() else { return }
        let polisher = polisher
        requests.start { [self] in
            let refined = await finishRequest(generation) { () async throws(PolishError) in
                try await polisher.refine(text: text, channel: channel, refinement: refinement)
            }
            if let refined {
                output = AppModel.editorText(fromMarkdown: refined)
                saveOutputToHistory()
            }
        }
    }

    private var outputMarkdown: String {
        RichText.markdown(from: RichTextBridge.attributedString(from: output))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
