import SwiftUI
import WritingAssistantCore

/// The writing sheet: formatting toolbar, editor, "Writing for" chips and the action row, as one
/// sheet of paper.
struct ComposerView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var inputController = RichTextController()
    @State private var inputLength = 0

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
                inputLength: inputLength,
                onClear: clear
            )
        }
        .background(theme.paper, in: sheetShape)
        .clipShape(sheetShape)
        .overlay(
            sheetShape
                .strokeBorder(borderColor, lineWidth: 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showsFocus)
        )
        .onChange(of: model.input, initial: true) { _, newValue in
            inputLength = InputLength.scalars(in: newValue)
        }
    }

    /// Resigns focus first: the clear is registered on the window's undo manager, and while an
    /// editor is first responder Edit > Undo goes to that editor's own (just emptied) stack.
    private func clear() {
        inputController.textView?.window?.makeFirstResponder(nil)
        model.clear(undoManager: undoManager)
    }

    private var sheetShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
    }

    private var showsFocus: Bool { inputController.isFocused && controlActiveState == .key }

    private var borderColor: Color {
        showsFocus ? theme.ink.opacity(0.6) : theme.rule
    }
}

/// How much input the polish pipeline counts against `PolishService.maxInputLength`.
enum InputLength {
    /// The meter shows once the input is over this many unicode scalars.
    static let meterThreshold = 15_000

    /// Unicode scalars of the trimmed Markdown the pipeline would send, the count
    /// `PolishService` checks against its limit. Markdown can be much longer than the plain
    /// text, so the plain length says nothing about it.
    static func scalars(in input: NSAttributedString) -> Int {
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
                isPolishing: model.isLoading && model.runningRefinement == nil,
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

/// The channel chips, in `Channel` order. ⌘1…⌘9 pick the first nine.
private struct ChannelChips: View {
    @Binding var selection: Channel
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Writing for")
                .font(.callout)
                .foregroundStyle(.secondary)
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(Channel.allCases.enumerated()), id: \.element) { index, channel in
                    chip(for: channel, number: index + 1)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Channel")
        }
    }

    @ViewBuilder private func chip(for channel: Channel, number: Int) -> some View {
        let button = Button(channel.shortName) { select(channel) }
            .buttonStyle(
                ChipStyle(
                    isSelected: selection == channel, selectionNamespace: selectionNamespace)
            )
            .accessibilityLabel(channel.displayName)
            .accessibilityAddTraits(selection == channel ? .isSelected : [])
        if number <= 9 {
            button
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                .help("\(channel.displayName) (⌘\(number))")
        } else {
            button.help(channel.displayName)
        }
    }

    private func select(_ channel: Channel) {
        if reduceMotion {
            selection = channel
        } else {
            withAnimation(.snappy(duration: 0.25)) { selection = channel }
        }
    }
}

private struct ActionRow: View {
    let inputLength: Int
    let isLoading: Bool
    let isPolishing: Bool
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
                isPolishing: isPolishing,
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
    @Environment(\.theme) private var theme

    private var limit: String { PolishService.maxInputLength.formatted() }

    var body: some View {
        Text("\(length.formatted()) / \(limit)")
            .font(.callout.monospacedDigit())
            .foregroundStyle(isOverLimit ? theme.redPencil : .secondary)
            .accessibilityLabel(
                isOverLimit
                    ? "\(length.formatted()) characters, over the limit of \(limit)"
                    : "\(length.formatted()) of \(limit) characters"
            )
    }
}

private struct PolishButton: View {
    let isLoading: Bool
    let isPolishing: Bool
    let isOverLimit: Bool
    let requestStartedAt: Date?
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            if !isLoading { action() }
        } label: {
            label
                .foregroundStyle(
                    isOverLimit ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.paper)
                )
                .frame(minWidth: 150)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isOverLimit)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(isPolishing ? "Polishing" : "Polish")
        .help(isOverLimit ? tooLongHelp : "Polish the text (⌘↵)")
    }

    @ViewBuilder private var label: some View {
        if isPolishing {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let showsElapsedAfter = 5

    var body: some View {
        if let startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(startedAt))
                Text(Self.text(elapsedSeconds: elapsed))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(elapsed)))
                    .animation(reduceMotion ? nil : .snappy, value: elapsed)
            }
        } else {
            Text(Self.text(elapsedSeconds: 0))
        }
    }

    private static func text(elapsedSeconds: Int) -> String {
        elapsedSeconds >= showsElapsedAfter ? "Polishing… \(elapsedSeconds) s" : "Polishing…"
    }
}
