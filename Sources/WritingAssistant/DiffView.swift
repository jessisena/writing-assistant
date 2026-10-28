import AppKit
import SwiftUI
import WritingAssistantCore

/// Read-only word diff of the input against the current output.
struct DiffView: View {
    let input: NSAttributedString
    let output: NSAttributedString

    var body: some View {
        let segments = DiffDisplay.segments(input: input, output: output)
        Text(DiffDisplay.attributedText(segments))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Changes")
            .accessibilityValue(DiffDisplay.accessibilityText(segments))
    }
}

/// Turns diff segments into styled text and a spoken description.
enum DiffDisplay {
    static let removedColor = Color.red
    static let addedColor = Color.green

    /// Diffs the plain text of `input` against the plain text of `output`.
    static func segments(input: NSAttributedString, output: NSAttributedString) -> [DiffSegment] {
        TextDiff.words(from: plainText(input), to: plainText(output))
    }

    /// All segments in order: removed text red with strikethrough, added text green, unchanged
    /// text unstyled.
    static func attributedText(_ segments: [DiffSegment]) -> AttributedString {
        segments.reduce(into: AttributedString()) { text, segment in
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .same:
                break
            case .removed:
                part.foregroundColor = removedColor
                part.strikethroughStyle = .single
            case .added:
                part.foregroundColor = addedColor
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
