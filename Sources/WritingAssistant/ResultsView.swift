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

    /// A refinement keeps the result on screen, so only a polish request shows the skeleton.
    private var phase: Phase {
        if model.isLoading && model.runningRefinement == nil { return .loading }
        return model.result == nil ? .idle : .result
    }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .loading:
                SkeletonCards().transition(.opacity)
            case .result:
                if let result = model.result {
                    VStack(spacing: 16) {
                        PolishedCard(model: model, result: result)
                        LearningSummaryCard(result: result)
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
            case .idle:
                IdleHint()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: phase)
    }
}

private struct IdleHint: View {
    var body: some View {
        Text("Your polished text and a short English tip will appear here.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkeletonCards: View {
    var body: some View {
        VStack(spacing: 16) {
            ResultCard(title: "Polished text") {
                Text(String(repeating: "Polished text is on its way. ", count: 8))
            }
            ResultCard(title: "English learning summary") {
                Text(String(repeating: "The summary is on its way. ", count: 5))
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working on your text")
    }
}

/// A flat card on `Theme.paper` with a `Theme.rule` border: a title, an optional accessory view
/// at the trailing edge, a hairline and the content.
struct ResultCard<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

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
            Theme.rule.frame(height: 1)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.rule))
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
                .help("Highlights what changed between your input and the polished text")
            }
            CopyButton(model: model)
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
            RichTextEditor(
                text: $model.output,
                controller: outputController,
                accessibilityLabel: "Polished text",
                minHeight: 80,
                maxHeight: 480
            )
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: EditorHeightKey.self, value: proxy.size.height)
            }
        )
    }
}

/// The detected language and the model, as one quiet line. A translation gets a capsule.
private struct ResultMeta: View {
    let result: PolishResult

    var body: some View {
        HStack(spacing: 8) {
            if result.wasTranslated {
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

    var body: some View {
        Button {
            Task { await model.copyResult() }
        } label: {
            Label(
                model.copied ? "Copied" : "Copy",
                systemImage: model.copied ? "checkmark" : "doc.on.doc"
            )
            .contentTransition(.symbolEffect(.replace))
        }
        .tint(model.copied ? .green : nil)
        .onChange(of: model.copied) { _, copied in
            if copied {
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment, performanceTime: .now)
            }
        }
    }
}

private struct RefinementRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Refine:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ForEach(Refinement.allCases) { refinement in
                Button {
                    model.refine(refinement)
                } label: {
                    ZStack {
                        Text(refinement.displayName)
                            .opacity(model.runningRefinement == refinement ? 0 : 1)
                        if model.runningRefinement == refinement {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .accessibilityLabel("Refine: \(refinement.displayName)")
                .help("Rewrites the polished text, including your edits")
            }
        }
        .disabled(!model.canRefine)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Refine polished text")
    }
}
