import AppKit
import SwiftUI
import WritingAssistantCore

/// Read-only word diff of the input against the current output, with a count of the changes and
/// a legend for the marks. The view is at least `minHeight` tall so that switching from the
/// editor doesn't move what is below.
struct DiffView: View {
    let input: NSAttributedString
    let output: NSAttributedString
    var minHeight: CGFloat = 80
    @Environment(\.theme) private var theme

    var body: some View {
        let segments = DiffDisplay.segments(input: input, output: output)
        VStack(alignment: .leading, spacing: 12) {
            Text(DiffDisplay.attributedText(segments, palette: theme))
                .font(.system(size: RichTextBridge.bodyFontSize))
                .lineSpacing(DiffDisplay.lineSpacing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Changes")
                .accessibilityValue(DiffDisplay.accessibilityText(segments))
            Spacer(minLength: 0)
            DiffFooter(changeCount: DiffDisplay.changeCount(segments))
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }
}

private struct DiffFooter: View {
    let changeCount: Int
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            Text(DiffDisplay.changeSummary(changeCount))
                .font(.callout.weight(.medium))
            LegendSwatch(label: "removed", color: theme.redPencil)
            LegendSwatch(label: "added", color: theme.marginGreen)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

private struct LegendSwatch: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}

/// Turns diff segments into styled text and a spoken description.
enum DiffDisplay {
    /// Extra space between lines that gives the diff the editor's line height.
    static let lineSpacing = RichTextBridge.bodyFontSize * (RichTextBridge.lineHeightMultiple - 1)

    /// "No changes", "1 change" or "6 changes".
    static func changeSummary(_ count: Int) -> String {
        switch count {
        case 0: "No changes"
        case 1: "1 change"
        default: "\(count) changes"
        }
    }

    /// Diffs the plain text of `input` against the plain text of `output`.
    static func segments(input: NSAttributedString, output: NSAttributedString) -> [DiffSegment] {
        TextDiff.words(from: plainText(input), to: plainText(output))
    }

    /// All segments in order: removed text in the palette's red pencil with strikethrough, added
    /// text in its margin green with an underline, each on a faint tint of its colour, and
    /// unchanged text unstyled.
    static func attributedText(
        _ segments: [DiffSegment], palette: ThemePalette
    ) -> AttributedString {
        let removedColor = palette.redPencil
        let addedColor = palette.marginGreen
        return segments.reduce(into: AttributedString()) { text, segment in
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .same:
                break
            case .removed:
                part.foregroundColor = removedColor
                part.backgroundColor = removedColor.opacity(0.12)
                part.strikethroughStyle = .single
            case .added:
                part.foregroundColor = addedColor
                part.backgroundColor = addedColor.opacity(0.14)
                part.underlineStyle = .single
            }
            text += part
        }
    }

    /// The number of changes: runs of removed and added segments. A removed segment followed by
    /// an added one is one change. Unchanged text made only of whitespace between two changes
    /// doesn't separate them, so a rewritten phrase counts once; any unchanged word does.
    static func changeCount(_ segments: [DiffSegment]) -> Int {
        var count = 0
        var inRun = false
        for segment in segments {
            if segment.kind != .same {
                if !inRun { count += 1 }
                inRun = true
            } else if !segment.text.allSatisfy(\.isWhitespace) {
                inRun = false
            }
        }
        return count
    }

    /// A VoiceOver description that names each change, such as
    /// "I, removed: will to review, added: 'll review, the doc".
    static func accessibilityText(_ segments: [DiffSegment]) -> String {
        let parts = segments.compactMap(spokenPart)
        guard segments.contains(where: { $0.kind != .same }) else {
            return (["No changes"] + parts).joined(separator: ": ")
        }
        return parts.joined(separator: ", ")
    }

    private static func spokenPart(_ segment: DiffSegment) -> String? {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? "whitespace" : trimmed
        switch segment.kind {
        case .same: return trimmed.isEmpty ? nil : trimmed
        case .removed: return "removed: \(text)"
        case .added: return "added: \(text)"
        }
    }

    private static func plainText(_ text: NSAttributedString) -> String {
        RichText.plainText(from: RichTextBridge.attributedString(from: text))
    }
}
