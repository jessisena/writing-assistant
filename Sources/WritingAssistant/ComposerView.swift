import SwiftUI
import WritingAssistantCore

/// Text input with its formatting toolbar, channel picker and Process button.
struct ComposerView: View {
    @Bindable var model: AppModel
    @State private var inputController = RichTextController()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                FormattingToolbar(controller: inputController)
                RichTextEditor(
                    text: $model.input,
                    controller: inputController,
                    accessibilityLabel: "Text to polish",
                    placeholder: "Paste your text here…"
                )
            }
            Picker("Channel", selection: $model.channel) {
                ForEach(Channel.allCases) { channel in
                    Text(channel.displayName).tag(channel)
                }
            }
            .pickerStyle(.radioGroup)
            ProcessRow(isLoading: model.isLoading) {
                Task { await model.process() }
            }
        }
    }
}

private struct ProcessRow: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                ZStack {
                    Text("Process").opacity(isLoading ? 0 : 1)
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel(isLoading ? "Processing" : "Process")
            Text("or ⌘↵")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
