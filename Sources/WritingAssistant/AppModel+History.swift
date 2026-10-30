import AppKit
import WritingAssistantCore

extension AppModel {
    /// Writes the output on screen, as Markdown, into the current history entry, so edits made
    /// in the output editor aren't lost. Does nothing when there is no current entry or the
    /// output hasn't changed, and blank output is never saved, so an entry keeps its last
    /// non-blank output. A save failure goes to the error banner.
    ///
    /// Called on copy, on clear, before a new request and when restoring another entry, so it
    /// doesn't write on every keystroke. Anything else that replaces `output` while an entry is
    /// current (such as a refinement) calls it after the new text is in `output`.
    func saveOutputToHistory() {
        do {
            try writeOutputToCurrentEntry()
        } catch {
            showBanner(error)
        }
    }

    /// Restores the entry with `id`: its input, output, mode, channel and result (learning
    /// summary, language, translation flag and model) come back, and it becomes the current
    /// entry. A channel now hidden in that mode is remembered, but the chips select the mode's
    /// first visible channel (see `AppModel.channel`). The output on screen is saved to its own
    /// entry first, and a failure to save it is shown in the error banner even when `id` is
    /// unknown. An unknown `id` leaves the screen as it is. Ignored while a request is running.
    func restoreHistoryEntry(id: UUID) {
        guard !isLoading else { return }
        var saveError: (any Error)?
        do {
            try writeOutputToCurrentEntry()
        } catch {
            saveError = error
        }
        if let entry = history.first(where: { $0.id == id }) {
            switchMode(to: entry.mode)
            channel = entry.channel
            show(
                Self.result(for: entry), input: Self.editorText(fromMarkdown: entry.inputMarkdown))
            currentHistoryID = entry.id
        }
        if let saveError {
            showBanner(saveError)
        }
    }

    /// Removes the entry with `id`. The text on screen stays, but it no longer belongs to an
    /// entry.
    func deleteHistoryEntry(id: UUID) {
        history.removeAll { $0.id == id }
        if currentHistoryID == id {
            currentHistoryID = nil
        }
        persistHistory()
    }

    /// Removes every entry. The text on screen stays.
    func clearHistory() {
        history = []
        currentHistoryID = nil
        persistHistory()
    }

    /// Adds a finished request as the newest entry and makes it current: a successful one, or a
    /// polish that showed its polished text before it failed or was cancelled.
    func recordHistory(_ result: PolishResult, input: String, channel: Channel, mode: Mode) {
        let entry = HistoryEntry(
            date: .now,
            channel: channel,
            mode: mode,
            inputMarkdown: input,
            outputMarkdown: result.polishedText,
            learningSummary: result.learningSummary,
            detectedLanguage: result.detectedLanguage,
            wasTranslated: result.wasTranslated,
            modelUsed: result.modelUsed
        )
        history.insert(entry, at: 0)
        history = Array(history.prefix(historyStore.limit))
        currentHistoryID = entry.id
        persistHistory()
    }

    /// Saves the output on screen to its entry, then detaches the screen from it.
    func leaveCurrentHistoryEntry() {
        saveOutputToHistory()
        currentHistoryID = nil
    }

    private func writeOutputToCurrentEntry() throws {
        guard let id = currentHistoryID,
            let index = history.firstIndex(where: { $0.id == id })
        else { return }
        let markdown = RichText.markdown(from: RichTextBridge.attributedString(from: output))
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            history[index].outputMarkdown != markdown
        else { return }
        history[index].outputMarkdown = markdown
        try saveHistory()
    }

    private func persistHistory() {
        do {
            try saveHistory()
        } catch {
            showBanner(error)
        }
    }

    /// Writes `history` to the store, unless saving is off for this session (see `savesHistory`).
    private func saveHistory() throws {
        guard savesHistory else { return }
        try historyStore.save(history)
    }

    private static func result(for entry: HistoryEntry) -> PolishResult {
        PolishResult(
            polishedText: entry.outputMarkdown,
            learningSummary: entry.learningSummary,
            detectedLanguage: entry.detectedLanguage,
            wasTranslated: entry.wasTranslated,
            modelUsed: entry.modelUsed
        )
    }
}
