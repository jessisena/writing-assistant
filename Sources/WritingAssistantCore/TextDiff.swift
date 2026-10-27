import Foundation

/// One run of text in a word diff.
public struct DiffSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case same
        case added
        case removed
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Word-level diff between two plain strings.
public enum TextDiff {
    /// Diffs `old` against `new` word by word.
    ///
    /// Both strings are split into words and whitespace runs, so a change in spacing shows up as
    /// its own segment. Emoji and other multi-scalar characters stay whole because tokens are
    /// built from `Character`s. Where text is replaced, the removed segment comes before the
    /// added one. Adjacent segments of the same kind are merged.
    ///
    /// - Parameters:
    ///   - old: The original text. Callers convert Markdown to plain text first.
    ///   - new: The changed text.
    /// - Returns: Segments that, read in order, rebuild `old` (`.same` + `.removed`) and `new`
    ///   (`.same` + `.added`). Empty when both inputs are empty.
    public static func words(from old: String, to new: String) -> [DiffSegment] {
        let oldTokens = tokens(old)
        let newTokens = tokens(new)
        let difference = newTokens.difference(from: oldTokens)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var segments: [DiffSegment] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldTokens.count || newIndex < newTokens.count {
            if removed.contains(oldIndex) {
                append(.removed, oldTokens[oldIndex], to: &segments)
                oldIndex += 1
            } else if inserted.contains(newIndex) {
                append(.added, newTokens[newIndex], to: &segments)
                newIndex += 1
            } else {
                append(.same, oldTokens[oldIndex], to: &segments)
                oldIndex += 1
                newIndex += 1
            }
        }
        return segments
    }

    /// Splits `text` into alternating runs of whitespace and non-whitespace characters.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentIsWhitespace = false
        for character in text {
            if !current.isEmpty && character.isWhitespace != currentIsWhitespace {
                result.append(current)
                current = ""
            }
            currentIsWhitespace = character.isWhitespace
            current.append(character)
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func append(
        _ kind: DiffSegment.Kind, _ text: String, to segments: inout [DiffSegment]
    ) {
        if let last = segments.last, last.kind == kind {
            segments[segments.count - 1] = DiffSegment(kind: kind, text: last.text + text)
        } else {
            segments.append(DiffSegment(kind: kind, text: text))
        }
    }
}
