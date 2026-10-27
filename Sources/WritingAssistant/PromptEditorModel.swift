import Foundation
import Observation
import WritingAssistantCore

/// State for the prompt editor: the saved text of every prompt file plus unsaved drafts.
///
/// A file has a draft only while its edited text differs from the saved text, so a file is
/// dirty exactly when it has a draft. Drafts are kept per file, so switching files never loses
/// unsaved edits. A file that couldn't be read has no saved text and is read-only until it
/// reads successfully or is restored, so an empty editor can never overwrite it.
@Observable @MainActor
final class PromptEditorModel {
    private let store: any PromptStoring
    private var savedTexts: [PromptFile: String] = [:]
    private var drafts: [PromptFile: String] = [:]
    private var errors: [PromptFile: String] = [:]

    var selection: PromptFile = .global {
        didSet { isConfirmingRestore = false }
    }

    private(set) var isConfirmingRestore = false

    init(store: any PromptStoring) {
        self.store = store
    }

    /// Text shown in the editor for the selected file. Editing clears the file's error message;
    /// edits to a read-only file are ignored.
    var draft: String {
        get { drafts[selection] ?? savedTexts[selection] ?? "" }
        set {
            guard let saved = savedTexts[selection], newValue != draft else { return }
            errors[selection] = nil
            drafts[selection] = newValue == saved ? nil : newValue
        }
    }

    /// Error for the selected file, shown inline under the editor.
    var errorMessage: String? { errors[selection] }

    var fileURL: URL { store.fileURL(selection) }

    var isCurrentFileDirty: Bool { isDirty(selection) }

    /// False while the selected file has no saved text, e.g. after a read error.
    var isCurrentFileEditable: Bool { savedTexts[selection] != nil }

    func isDirty(_ file: PromptFile) -> Bool {
        drafts[file] != nil
    }

    /// Re-reads every file without an unsaved draft, picking up edits made outside the app.
    func reload() {
        for file in PromptFile.allCases where !isDirty(file) {
            load(file)
        }
    }

    func save() {
        let file = selection
        guard savedTexts[file] != nil, let text = drafts[file] else { return }
        do {
            try store.write(text, to: file)
            savedTexts[file] = text
            drafts[file] = nil
            errors[file] = nil
        } catch {
            errors[file] = Self.message(for: error, saving: file)
        }
    }

    func revert() {
        drafts[selection] = nil
        errors[selection] = nil
    }

    func requestRestore() {
        isConfirmingRestore = true
    }

    func cancelRestore() {
        isConfirmingRestore = false
    }

    func confirmRestore() {
        let file = selection
        isConfirmingRestore = false
        do {
            try store.restoreDefault(file)
        } catch {
            errors[file] = "Couldn't restore \(file.displayName): \(error.localizedDescription)"
            return
        }
        drafts[file] = nil
        load(file)
    }

    private func load(_ file: PromptFile) {
        do {
            savedTexts[file] = try store.read(file)
            errors[file] = nil
        } catch {
            savedTexts[file] = nil
            errors[file] = "Couldn't read \(file.displayName): \(error.localizedDescription)"
        }
    }

    private static func message(for error: any Error, saving file: PromptFile) -> String {
        if let validation = error as? PromptValidationError {
            return validation.localizedDescription
        }
        return "Couldn't save \(file.displayName): \(error.localizedDescription)"
    }
}
