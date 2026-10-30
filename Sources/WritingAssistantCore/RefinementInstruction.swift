import Foundation

/// What a refinement asks for: one of the preset refinement files, or the user's own words.
public enum RefinementInstruction: Sendable, Hashable {
    case preset(Refinement)
    /// The user's own instruction, such as "mention the deadline is Friday". It goes into the
    /// refine prompt's instruction section as typed, after `validated()`.
    case custom(String)

    /// The most characters a custom instruction may have, counted after trimming.
    public static let maxCustomLength = 500

    /// A short name for logs: the preset's raw value, or `custom`.
    public var logName: String {
        switch self {
        case .preset(let refinement): refinement.rawValue
        case .custom: "custom"
        }
    }

    /// The instruction ready to send. A preset is returned as is. A custom instruction loses the
    /// prompt placeholders it contains (so it can't pull another prompt section in) and its
    /// leading and trailing whitespace.
    ///
    /// - Throws: `.emptyInstruction` when nothing is left of a custom instruction, or
    ///   `.instructionTooLong` when it has more than `maxCustomLength` characters.
    public func validated() throws(PolishError) -> RefinementInstruction {
        guard case .custom(let text) = self else { return self }
        let cleaned = Self.withoutPlaceholders(text)
        if cleaned.isEmpty {
            throw .emptyInstruction
        }
        if cleaned.count > Self.maxCustomLength {
            throw .instructionTooLong(limit: Self.maxCustomLength)
        }
        return .custom(cleaned)
    }

    /// `text` without any prompt placeholder, trimmed. Removal repeats until none is left, so
    /// one placeholder nested inside another can't leave a new one behind.
    static func withoutPlaceholders(_ text: String) -> String {
        let placeholders = [
            PromptFile.alwaysPlaceholder, PromptFile.channelPlaceholder,
            PromptFile.learningSummaryPlaceholder, PromptFile.instructionPlaceholder,
        ]
        var cleaned = text
        while let placeholder = placeholders.first(where: cleaned.contains) {
            cleaned = cleaned.replacingOccurrences(of: placeholder, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
