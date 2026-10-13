import AppKit
import SwiftUI
import WritingAssistantCore

/// Settings-window editor for the global rules and the per-channel prompt files.
struct PromptEditorView: View {
    @State private var model: PromptEditorModel

    init(store: any PromptStoring) {
        _model = State(initialValue: PromptEditorModel(store: store))
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

    var body: some View {
        List(PromptFile.allCases, selection: $model.selection) { file in
            HStack {
                Text(file.displayName)
                Spacer()
                if model.isDirty(file) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("Unsaved changes")
                }
            }
            .tag(file)
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Prompt files")
    }
}

private struct PromptEditorDetail: View {
    @Bindable var model: PromptEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.selection.displayName)
                .font(.title3.weight(.semibold))
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

    var body: some View {
        HStack {
            Button("Save") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.isCurrentFileDirty)
                .accessibilityHint("Saves this prompt file")
            Button("Revert") { model.revert() }
                .disabled(!model.isCurrentFileDirty)
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
