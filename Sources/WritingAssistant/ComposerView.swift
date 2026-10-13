import SwiftUI
import WritingAssistantCore

/// Text input, channel picker and Process button.
struct ComposerView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InputEditor(text: $model.inputText)
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

private struct InputEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 160)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Paste your text here…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(.separator)
            )
            .accessibilityLabel("Text to polish")
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
