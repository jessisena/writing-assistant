import SwiftUI
import WritingAssistantCore

/// The toolbar button (⌘Y) that opens the history popover. Disabled while a request runs.
struct HistoryButton: View {
    let model: AppModel
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
        }
        .keyboardShortcut("y", modifiers: .command)
        .disabled(model.isLoading)
        .help("Show past requests (⌘Y)")
        .accessibilityHint("Shows past requests to restore or delete")
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            HistoryView(model: model) { isShowing = false }
        }
    }
}

/// Lists past requests, newest first. Selecting one restores it and closes the popover. Rows and
/// Clear History are disabled while a request runs.
struct HistoryView: View {
    let model: AppModel
    let onRestore: () -> Void
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if model.history.isEmpty {
                Text("No history yet. Processed texts appear here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                HistoryList(model: model, onRestore: onRestore)
                    .disabled(model.isLoading)
            }
            Divider()
            if isConfirmingClear {
                ClearHistoryConfirmationRow(
                    onCancel: { isConfirmingClear = false },
                    onConfirm: {
                        model.clearHistory()
                        isConfirmingClear = false
                    }
                )
            } else {
                HStack {
                    Spacer()
                    Button("Clear History…") { isConfirmingClear = true }
                        .disabled(model.history.isEmpty || model.isLoading)
                        .accessibilityHint("Asks before deleting every past request")
                }
            }
        }
        .padding(12)
        .frame(width: 380)
    }
}

private struct HistoryList: View {
    let model: AppModel
    let onRestore: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(model.history) { entry in
                    HistoryRow(
                        entry: entry,
                        isCurrent: entry.id == model.currentHistoryID,
                        onRestore: {
                            model.restoreHistoryEntry(id: entry.id)
                            onRestore()
                        },
                        onDelete: { model.deleteHistoryEntry(id: entry.id) }
                    )
                }
            }
        }
        .frame(maxHeight: 360)
        .accessibilityLabel("Past requests")
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let isCurrent: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    @Environment(\.theme) private var theme

    private var preview: String { Self.firstLine(of: entry.outputMarkdown) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onRestore) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.date, format: .relative(presentation: .named))
                        Text("·")
                        Text(entry.channel.displayName)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(preview)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Restores this text")
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete from history")
            .accessibilityLabel("Delete \(preview)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isCurrent ? theme.ink.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    private var accessibilityLabel: String {
        let date = entry.date.formatted(.relative(presentation: .named))
        let current = isCurrent ? ", shown now" : ""
        return "\(entry.channel.displayName), \(date)\(current): \(preview)"
    }

    /// The first non-empty line of the output as plain text, without Markdown markers.
    static func firstLine(of markdown: String) -> String {
        let plain = RichText.plainText(from: RichText.attributedString(fromMarkdown: markdown))
        let line = plain.split(whereSeparator: \.isNewline).first.map(String.init)
        return line ?? "(empty)"
    }
}

private struct ClearHistoryConfirmationRow: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Delete every past request?")
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Clear", role: .destructive, action: onConfirm)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
    }
}
