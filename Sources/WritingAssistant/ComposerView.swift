import SwiftUI
import WritingAssistantCore

/// The writing sheet: formatting toolbar, editor, "Writing for" chips and the action row, as one
/// sheet of paper.
struct ComposerView: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inputController = RichTextController()

    private static let cornerRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            FormattingToolbar(controller: inputController)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            RichTextEditor(
                text: $model.input,
                controller: inputController,
                accessibilityLabel: "Text to polish",
                placeholder: "Paste or type the text you want to polish…",
                minHeight: 220,
                isBordered: false
            )
            Divider()
            ComposerFooter(
                model: model,
                inputLength: InputLength.scalars(in: model.input),
                onClear: { model.clear(undoManager: undoManager) }
            )
        }
        .background(Theme.paper, in: sheetShape)
        .clipShape(sheetShape)
        .overlay(sheetShape.strokeBorder(borderColor, lineWidth: 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: inputController.isFocused)
    }

    private var sheetShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
    }

    private var borderColor: Color {
        inputController.isFocused ? Theme.ink.opacity(0.6) : Theme.rule
    }
}

/// How much input the polish pipeline counts against `PolishService.maxInputLength`.
enum InputLength {
    /// The meter shows once the input is over this many unicode scalars.
    static let meterThreshold = 15_000

    /// Unicode scalars of the trimmed Markdown the pipeline would send. The Markdown is only
    /// built when the plain text is long enough for the result to matter, because Markdown
    /// is never shorter than the plain text it comes from.
    static func scalars(in input: NSAttributedString) -> Int {
        guard input.length > meterThreshold / 2 else { return input.length }
        let markdown = RichText.markdown(from: RichTextBridge.attributedString(from: input))
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }
}

private struct ComposerFooter: View {
    @Bindable var model: AppModel
    let inputLength: Int
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChannelChips(selection: $model.channel)
            ActionRow(
                inputLength: inputLength,
                isLoading: model.isLoading,
                canClear: model.canClear,
                requestStartedAt: model.requestStartedAt,
                onPolish: model.startProcessing,
                onClear: onClear,
                onCancel: model.cancel
            )
        }
        .padding(12)
    }
}

private struct ChannelChips: View {
    @Binding var selection: Channel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Writing for")
                .font(.callout)
                .foregroundStyle(.secondary)
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Channel.allCases) { channel in
                    Button(channel.shortName) { selection = channel }
                        .buttonStyle(ChipStyle(isSelected: selection == channel))
                        .help(channel.displayName)
                        .accessibilityLabel(channel.displayName)
                        .accessibilityAddTraits(selection == channel ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Channel")
        }
    }
}

private struct ChipStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(isSelected ? Theme.ink : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill(isPressed: configuration.isPressed), in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Theme.ink : Theme.rule, lineWidth: 1))
            .contentShape(Capsule())
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isSelected)
    }

    private func fill(isPressed: Bool) -> Color {
        if isSelected { return Theme.ink.opacity(0.15) }
        if isPressed { return Color.primary.opacity(0.10) }
        return isHovered ? Color.primary.opacity(0.06) : .clear
    }
}

private struct ActionRow: View {
    let inputLength: Int
    let isLoading: Bool
    let canClear: Bool
    let requestStartedAt: Date?
    let onPolish: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    private var isOverLimit: Bool { inputLength > PolishService.maxInputLength }

    var body: some View {
        HStack(spacing: 12) {
            if inputLength > InputLength.meterThreshold {
                LengthMeter(length: inputLength, isOverLimit: isOverLimit)
            }
            Spacer()
            if isLoading {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .help("Stop the request (Esc)")
            } else if canClear {
                Button("Clear", action: onClear)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("k", modifiers: .command)
                    .help("Clear the input and results (⌘K)")
            }
            PolishButton(
                isLoading: isLoading,
                isOverLimit: isOverLimit,
                requestStartedAt: requestStartedAt,
                action: onPolish
            )
        }
    }
}

private struct LengthMeter: View {
    let length: Int
    let isOverLimit: Bool

    private var limit: String { PolishService.maxInputLength.formatted() }

    var body: some View {
        Text("\(length.formatted()) / \(limit)")
            .font(.callout.monospacedDigit())
            .foregroundStyle(isOverLimit ? Theme.redPencil : .secondary)
            .accessibilityLabel(
                isOverLimit
                    ? "\(length.formatted()) characters, over the limit of \(limit)"
                    : "\(length.formatted()) of \(limit) characters"
            )
    }
}

private struct PolishButton: View {
    let isLoading: Bool
    let isOverLimit: Bool
    let requestStartedAt: Date?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label.frame(minWidth: 150)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isLoading || isOverLimit)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(isLoading ? "Polishing" : "Polish")
        .help(isOverLimit ? tooLongHelp : "Polish the text (⌘↵)")
    }

    @ViewBuilder private var label: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                ProgressText(startedAt: requestStartedAt)
            }
        } else {
            HStack(spacing: 8) {
                Text("Polish")
                Text("⌘↵")
                    .opacity(0.65)
                    .accessibilityHidden(true)
            }
        }
    }

    private var tooLongHelp: String {
        "The text is over the \(PolishService.maxInputLength.formatted()) character limit. "
            + "Shorten it to polish."
    }
}

/// "Polishing…", with the seconds elapsed once the request has run for a while.
private struct ProgressText: View {
    let startedAt: Date?

    private static let showsElapsedAfter = 5

    var body: some View {
        if let startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(startedAt))
                Text(Self.text(elapsedSeconds: elapsed)).monospacedDigit()
            }
        } else {
            Text(Self.text(elapsedSeconds: 0))
        }
    }

    private static func text(elapsedSeconds: Int) -> String {
        elapsedSeconds >= showsElapsedAfter ? "Polishing… \(elapsedSeconds) s" : "Polishing…"
    }
}
