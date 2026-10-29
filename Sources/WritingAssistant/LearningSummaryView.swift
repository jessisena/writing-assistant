import SwiftUI
import WritingAssistantCore

/// The English learning summary card: corrections, grammar insight and new vocabulary.
struct LearningSummaryCard: View {
    let result: PolishResult

    var body: some View {
        ResultCard(title: "English learning summary") {
            if result.wasTranslated {
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
            Text(label)
                .font(.subheadline.weight(.semibold))
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
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.ink.opacity(0.06))
            .overlay(alignment: .leading) {
                Rectangle().fill(theme.ink).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
