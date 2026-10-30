import AppKit
import SwiftUI
import WritingAssistantCore

/// Polished text and learning summary cards, skeleton cards while loading, or a hint when idle.
struct ResultsView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase {
        case idle, loading, result
    }

    /// A polish clears the result when it starts, so the skeleton shows until its preview or
    /// final result arrives. A refinement keeps the result on screen.
    private var phase: Phase {
        if model.result != nil { return .result }
        return model.isLoading ? .loading : .idle
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch phase {
            case .loading:
                SkeletonCards(includesSummary: model.includesLearningSummary)
                    .transition(.opacity)
            case .result:
                if let result = model.result {
                    VStack(spacing: 16) {
                        PolishedCard(model: model, result: result)
                        if model.isAwaitingSummary {
                            SummarySkeletonCard()
                        } else if showsSummary(of: result) {
                            LearningSummaryCard(result: result)
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity)
                    )
                }
            case .idle:
                IdleHint(includesSummary: model.includesLearningSummary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: phase)
    }

    /// The card shows a summary whenever the result has one (even a history entry from before the
    /// setting was turned off), and explains a translation's missing summary while the setting is
    /// on. English text without a summary (setting off, cancelled or failed) gets no card.
    private func showsSummary(of result: PolishResult) -> Bool {
        result.learningSummary != nil || (result.wasTranslated && model.includesLearningSummary)
    }
}

private struct IdleHint: View {
    let includesSummary: Bool

    var body: some View {
        Text(
            includesSummary
                ? "Your polished text and a short English tip will appear here."
                : "Your polished text will appear here."
        )
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkeletonCards: View {
    let includesSummary: Bool

    var body: some View {
        VStack(spacing: 16) {
            ResultCard(title: "Polished text") {
                Text(String(repeating: "Polished text is on its way. ", count: 8))
                    .shimmering()
            }
            .redacted(reason: .placeholder)
            if includesSummary {
                SummarySkeletonCard()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working on your text")
    }
}

/// A redacted learning summary card, shown while the summary is on its way.
private struct SummarySkeletonCard: View {
    var body: some View {
        ResultCard(title: "English learning summary") {
            Text(String(repeating: "The summary is on its way. ", count: 5))
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working on the English learning summary")
    }
}

/// A flat card on the theme's paper with a rule border: a title, an optional accessory view at
/// the trailing edge, a hairline and the content.
struct ResultCard<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    init(
        title: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(title)
                accessory
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            theme.rule.frame(height: 1)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
        .background(theme.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.rule))
    }
}

private struct EditorHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PolishedCard: View {
    @Bindable var model: AppModel
    let result: PolishResult
    @State private var outputController = RichTextController()
    @State private var editorHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsDiff: Bool {
        model.showsChanges && !result.wasTranslated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            card
                .opacity(model.runningRefinement == nil ? 1 : 0.5)
                .allowsHitTesting(model.runningRefinement == nil)
            RefinementRow(model: model)
        }
    }

    private var card: some View {
        ResultCard(title: "Polished text") {
            ResultMeta(result: result)
            Spacer()
            if !result.wasTranslated {
                Picker("Show changes", selection: $model.showsChanges) {
                    Text("Edit").tag(false)
                    Text("Changes").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(model.isStreamingText)
                .help("Highlights what changed between your input and the polished text")
            }
            CopyButton(model: model)
                .disabled(model.isStreamingText)
        } content: {
            ZStack(alignment: .top) {
                if showsDiff {
                    DiffView(input: model.input, output: model.output, minHeight: editorHeight)
                        .transition(.opacity)
                } else {
                    editor.transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showsDiff)
            .onPreferenceChange(EditorHeightKey.self) { height in
                if height > 0 { editorHeight = height }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormattingToolbar(controller: outputController)
                .disabled(model.isStreamingText)
            // Read-only while the text streams in: the next update would replace any edit.
            RichTextEditor(
                text: $model.output,
                controller: outputController,
                accessibilityLabel: "Polished text",
                minHeight: 80,
                maxHeight: 480,
                isEditable: !model.isStreamingText
            )
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: EditorHeightKey.self, value: proxy.size.height)
            }
        )
    }
}

/// The detected language and the model, as one quiet line. A translation gets a capsule. An
/// unknown language (the reply hasn't named it yet, or never did) shows only the model.
private struct ResultMeta: View {
    let result: PolishResult

    private var isLanguageKnown: Bool { result.detectedLanguage != "Unknown" }

    var body: some View {
        HStack(spacing: 8) {
            if !isLanguageKnown {
                Text(result.modelUsed)
                    .accessibilityLabel("Model \(result.modelUsed)")
            } else if result.wasTranslated {
                Text("Translated from \(result.detectedLanguage)")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.tint))
                Text(result.modelUsed)
                    .accessibilityLabel("Model \(result.modelUsed)")
            } else {
                Text("\(result.detectedLanguage) · \(result.modelUsed)")
                    .accessibilityLabel("\(result.detectedLanguage), model \(result.modelUsed)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct CopyButton: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Task { await model.copyResult() }
        } label: {
            Label(
                model.copied ? "Copied" : "Copy",
                systemImage: model.copied ? "checkmark" : "doc.on.doc"
            )
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: model.copyGeneration)
            .symbolEffectsRemoved(reduceMotion)
        }
        .tint(model.copied ? .green : nil)
        .sensoryFeedback(.alignment, trigger: model.copyGeneration)
    }
}

/// "Refine:", a button per refinement and a field for the user's own instruction, wrapping to
/// more rows when the window is narrow.
private struct RefinementRow: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Refine:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Refinement.allCases) { refinement in
                    Button {
                        model.refine(refinement)
                    } label: {
                        ZStack {
                            Text(refinement.displayName)
                                .opacity(model.runningRefinement == .preset(refinement) ? 0 : 1)
                            if model.runningRefinement == .preset(refinement) {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(ChipStyle())
                    .accessibilityLabel("Refine: \(refinement.displayName)")
                    .help("Rewrites the polished text, including your edits")
                }
                CustomRefinementField(model: model)
            }
        }
        .disabled(!model.canRefine)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Refine polished text")
    }
}

/// A capsule field after the refine buttons for the user's own instruction ("mention the
/// deadline is Friday"). Return sends it and a spinner shows while it runs; the field gives up
/// focus meanwhile, so Esc reaches Cancel, and takes it back when the run ends. Close to the
/// length limit a count appears, in red pencil once over it.
private struct CustomRefinementField: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    private static let limit = RefinementInstruction.maxCustomLength
    private static let countThreshold = limit - 100

    private var isRunning: Bool {
        if case .custom = model.runningRefinement { return true }
        return false
    }

    private var length: Int {
        model.customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("Or type your own, e.g. less emoji", text: $model.customInstruction)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { model.refineWithCustomInstruction() }
                .accessibilityLabel("Refine with your own instruction")
            trailing
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(width: 260)
        .background {
            Capsule().strokeBorder(isFocused ? theme.ink : theme.rule, lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
        .onChange(of: isRunning) { _, running in
            isFocused = !running
        }
        .help("Type your own instruction, such as \"less emoji\", and press Return")
    }

    @ViewBuilder private var trailing: some View {
        if isRunning {
            ProgressView().controlSize(.small)
        } else if length > Self.countThreshold {
            Text("\(length)/\(Self.limit)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(length > Self.limit ? theme.redPencil : Color.secondary)
                .accessibilityLabel("\(length) of \(Self.limit) characters")
        }
    }
}

extension View {
    /// Sweeps a brighter band across a redacted placeholder, left to right, while it's on screen.
    /// Reduce Motion leaves the placeholder still.
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false

    private static let dimmed = Color.black.opacity(0.45)

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .mask { band }
                .onAppear { isSweeping = true }
        }
    }

    /// A gradient three times the content's width, dim except for a bright stripe in its middle,
    /// slid from the stripe left of the content to the stripe right of it.
    private var band: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                stops: [
                    .init(color: Self.dimmed, location: 0.4),
                    .init(color: .black, location: 0.5),
                    .init(color: Self.dimmed, location: 0.6),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 3, height: proxy.size.height)
            .offset(x: isSweeping ? 0 : -width * 2)
            .animation(
                .linear(duration: 1.4).repeatForever(autoreverses: false), value: isSweeping)
        }
    }
}
