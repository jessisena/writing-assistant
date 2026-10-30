import Foundation
import WritingAssistantCore

extension AppModel {
    /// True when there is a polished result with non-blank output and no request is running.
    var canRefine: Bool {
        !isLoading && result != nil && !outputMarkdown.isEmpty
    }

    /// Asks Claude to apply the preset `refinement` to the current, possibly edited, output.
    /// See `refine(with:)`.
    func refine(_ refinement: Refinement) {
        refine(with: .preset(refinement))
    }

    /// Asks Claude to apply `customInstruction` to the current, possibly edited, output, the
    /// same way a preset refinement does (see `refine(with:)`).
    ///
    /// A blank instruction does nothing. One that is too long shows the limit in the error
    /// banner and isn't sent. A successful refinement empties `customInstruction`; a failed or
    /// cancelled one keeps it, so the user can try again. Ignored unless `canRefine`.
    func refineWithCustomInstruction() {
        guard canRefine else { return }
        let instruction: RefinementInstruction
        do {
            instruction = try RefinementInstruction.custom(customInstruction).validated()
        } catch .emptyInstruction {
            return
        } catch {
            showBanner(error)
            return
        }
        refine(with: instruction) { [self] in customInstruction = "" }
    }

    /// Asks Claude to apply `instruction` to the current, possibly edited, output.
    ///
    /// The output is sent as Markdown with the current history entry's channel (the one it was
    /// polished for), or the selected channel when there is no current entry, and is replaced by
    /// the answer. The result keeps its learning summary and language, since a summary of the
    /// model's own text means nothing. The refined output is saved to the current history entry;
    /// the learning log is left alone. Runs in `requests`, so `cancel()` stops it. Ignored
    /// unless `canRefine`.
    ///
    /// - Parameter onSuccess: Runs after the refined output is shown and saved.
    private func refine(
        with instruction: RefinementInstruction, onSuccess: @escaping @MainActor () -> Void = {}
    ) {
        guard canRefine else { return }
        let text = outputMarkdown
        let channel = history.first { $0.id == currentHistoryID }?.channel ?? channel
        guard let generation = beginRequest(refinement: instruction) else { return }
        let polisher = polisher
        requests.start { [self] in
            let refined = await finishRequest(generation) { () async throws(PolishError) in
                try await polisher.refine(text: text, channel: channel, refinement: instruction)
            }
            if let refined {
                output = AppModel.editorText(fromMarkdown: refined)
                saveOutputToHistory()
                onSuccess()
            }
        }
    }

    private var outputMarkdown: String {
        RichText.markdown(from: RichTextBridge.attributedString(from: output))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
