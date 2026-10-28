import AppKit
import SwiftUI
import WritingAssistantCore

/// Settings-window editor for the global rules and the per-channel prompt files.
struct PromptEditorView: View {
    @State private var model: PromptEditorModel

    init(store: any PromptStoring, newerDefaults: Set<PromptFile> = []) {
        _model = State(initialValue: PromptEditorModel(store: store, newerDefaults: newerDefaults))
    }

    var body: some View {
        HStack(spacing: 0) {
            PromptFileSidebar(model: model)
                .frame(width: 220)
            Divider()
            PromptEditorDetail(model: model)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { model.reload() }
    }
}

private struct PromptFileSidebar: View {
    @Bindable var model: PromptEditorModel

    private var promptFiles: [PromptFile] {
        PromptFile.allCases.filter { !$0.isRefinement }
    }

    private var refinementFiles: [PromptFile] {
        PromptFile.allCases.filter(\.isRefinement)
    }

    var body: some View {
        List(selection: $model.selection) {
            Section("Prompts") {
                ForEach(promptFiles) { PromptFileRow(model: model, file: $0) }
            }
            Section("Refinements") {
                ForEach(refinementFiles) { PromptFileRow(model: model, file: $0) }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Prompt files")
    }
}

private struct PromptFileRow: View {
    let model: PromptEditorModel
    let file: PromptFile

    var body: some View {
        HStack {
            Text(file.displayName)
            Spacer()
            if model.hasNewerDefault(file) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.orange)
                    .help("A newer default is available")
                    .accessibilityLabel("Newer default available")
            }
            if model.isDirty(file) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Unsaved changes")
            }
        }
        .tag(file)
    }
}

extension PromptFile {
    fileprivate var isRefinement: Bool {
        if case .refinement = self { return true }
        return false
    }
}

private struct PromptEditorDetail: View {
    @Bindable var model: PromptEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.selection.displayName)
                .font(.title3.weight(.semibold))
            if model.isNewerDefaultAvailable && !model.isConfirmingRestore {
                NewerDefaultBanner(model: model)
            }
            TextEditor(text: $model.draft)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .disabled(!model.isCurrentFileEditable)
                .accessibilityLabel("\(model.selection.displayName) prompt text")
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(message)")
            }
            if model.isConfirmingRestore {
                RestoreConfirmationRow(model: model)
            }
            PromptEditorActions(model: model)
            Divider()
            PromptEditorFooter(path: model.fileURL.path)
        }
        .padding(16)
    }
}

private struct PromptEditorActions: View {
    let model: PromptEditorModel

    private var hasEditableChanges: Bool {
        model.isCurrentFileEditable && model.isCurrentFileDirty
    }

    var body: some View {
        HStack {
            Button("Save") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasEditableChanges)
                .accessibilityHint("Saves this prompt file")
            Button("Revert") { model.revert() }
                .disabled(!hasEditableChanges)
                .accessibilityHint("Discards unsaved changes to this prompt file")
            Spacer()
            Button("Restore Default…") { model.requestRestore() }
                .disabled(model.isConfirmingRestore)
                .accessibilityHint("Replaces this prompt file with the bundled default text")
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([model.fileURL])
            }
            .accessibilityHint("Shows this prompt file in Finder")
        }
    }
}

private struct NewerDefaultBanner: View {
    let model: PromptEditorModel

    var body: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            Text("A newer default is available. You've edited this file, so it wasn't updated.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Keep mine") { model.keepMine() }
                .accessibilityHint("Keeps your version and hides this message")
            Button("Restore Default…") { model.requestRestore() }
                .accessibilityHint("Replaces this prompt file with the newer default text")
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
    }
}

private struct RestoreConfirmationRow: View {
    let model: PromptEditorModel

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Replace with the default text? Your edits to this file will be lost.")
            Spacer()
            Button("Cancel") { model.cancelRestore() }
                .keyboardShortcut(.cancelAction)
            Button("Restore", role: .destructive) { model.confirmRestore() }
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
    }
}

private struct PromptEditorFooter: View {
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("File path: \(path)")
            Text("Changes apply to the next request.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
