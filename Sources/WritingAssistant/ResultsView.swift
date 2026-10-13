import SwiftUI
import WritingAssistantCore

/// Polished text and learning summary cards, or skeleton cards while loading.
struct ResultsView: View {
    let result: PolishResult?
    let isLoading: Bool
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        if isLoading {
            SkeletonCards()
        } else if let result {
            VStack(spacing: 16) {
                PolishedCard(result: result, copied: copied, onCopy: onCopy)
                LearningSummaryCard(result: result)
            }
        }
    }
}

private struct SkeletonCards: View {
    var body: some View {
        VStack(spacing: 16) {
            Card(title: "Polished Text") {
                Text(String(repeating: "Polished text is on its way. ", count: 8))
            }
            Card(title: "English Learning Summary") {
                Text(String(repeating: "The summary is on its way. ", count: 5))
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Processing your text")
    }
}

private struct Card<Accessory: View, Content: View>: View {
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
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(title)
                Spacer()
                accessory
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            Divider()
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}

private struct PolishedCard: View {
    let result: PolishResult
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        Card(title: "Polished Text") {
            HStack(spacing: 10) {
                LanguageLabel(result: result)
                Text(result.modelUsed)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Model \(result.modelUsed)")
                Button(copied ? "Copied" : "Copy", action: onCopy)
                    .tint(copied ? .green : nil)
            }
        } content: {
            Text(result.polishedText)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}

private struct LanguageLabel: View {
    let result: PolishResult

    private var text: String {
        result.wasTranslated
            ? "Translated from \(result.detectedLanguage)" : result.detectedLanguage
    }

    private var style: AnyShapeStyle {
        result.wasTranslated ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(style)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(
                Capsule().strokeBorder(
                    result.wasTranslated ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator)
                )
            )
    }
}

private struct LearningSummaryCard: View {
    let result: PolishResult

    var body: some View {
        Card(title: "English Learning Summary") {
            if result.wasTranslated || result.learningSummary == nil {
                NoteText(
                    "Original was in \(result.detectedLanguage) — the summary is only shown when "
                        + "you write directly in English, since that's when your own English "
                        + "patterns are visible."
                )
            } else if let summary = result.learningSummary, summary.isEmpty {
                NoteText("Nothing to flag here — the text was already clean.")
            } else if let summary = result.learningSummary {
                SummarySections(summary: summary)
            }
        }
    }
}

private struct NoteText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

private struct SummarySections: View {
    let summary: LearningSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !summary.corrections.isEmpty {
                SummarySection(label: "Corrections") {
                    ForEach(Array(summary.corrections.enumerated()), id: \.offset) { _, item in
                        CorrectionRow(correction: item)
                    }
                }
            }
            if !summary.grammarInsight.isEmpty {
                SummarySection(label: "Grammar insight") {
                    GrammarInsight(text: summary.grammarInsight)
                }
            }
            if !summary.vocabulary.isEmpty {
                SummarySection(label: "New vocabulary") {
                    ForEach(Array(summary.vocabulary.enumerated()), id: \.offset) { _, item in
                        VocabularyRow(item: item)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct SummarySection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(label)
            content
        }
    }
}

private struct CorrectionRow: View {
    let correction: Correction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(correction.original)
                    .strikethrough()
                    .italic()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Original: \(correction.original)")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(correction.corrected)
                    .fontWeight(.medium)
                    .accessibilityLabel("Corrected: \(correction.corrected)")
            }
            Text(correction.why)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GrammarInsight: View {
    let text: String

    var body: some View {
        Text(text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                Rectangle().fill(.tint).frame(width: 3)
            }
    }
}

private struct VocabularyRow: View {
    let item: VocabularyItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            (Text(item.term).bold().foregroundStyle(.tint)
                + Text(" — \(item.meaning)").foregroundStyle(.secondary))
            Text("\"\(item.example)\"")
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
        }
    }
}
