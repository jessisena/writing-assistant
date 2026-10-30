import Foundation

/// Builds the system prompts from the prompt files. Kotlin's `PromptAssembler` mirrors this.
///
/// Each template's placeholders are replaced by the trimmed section files they name. A section
/// file is only read when its placeholder is in the template, so a `polish.txt` edited before a
/// section existed keeps working unchanged: it simply has nothing to fill.
extension PromptStoring {
    /// The polish prompt for `channel`.
    ///
    /// `polish.txt` with the shared rules, the channel guidelines and, only when
    /// `learningSummary` is true, the learning summary section. When it is false the
    /// placeholder is removed, so the prompt carries no summary instructions at all.
    ///
    /// - Throws: `PromptStoreError` when a needed prompt file couldn't be read.
    public func assemble(for channel: Channel, learningSummary: Bool) throws -> String {
        try fill(
            .global,
            [
                (PromptFile.alwaysPlaceholder, .always),
                (PromptFile.channelPlaceholder, .channel(channel)),
                (PromptFile.learningSummaryPlaceholder, learningSummary ? .learningSummary : nil),
            ])
    }

    /// The refine prompt: `refine.txt` with the shared rules, the channel guidelines and the
    /// refinement instruction.
    ///
    /// - Throws: `PromptStoreError` when a needed prompt file couldn't be read.
    public func assembleRefinement(
        _ refinement: Refinement, for channel: Channel
    ) throws -> String {
        try fill(
            .refine,
            [
                (PromptFile.alwaysPlaceholder, .always),
                (PromptFile.channelPlaceholder, .channel(channel)),
                (PromptFile.instructionPlaceholder, .refinement(refinement)),
            ])
    }

    /// Replaces each placeholder in `template` with its trimmed file, in order; a nil file
    /// removes the placeholder. The result is trimmed.
    private func fill(
        _ template: PromptFile, _ sections: [(placeholder: String, file: PromptFile?)]
    ) throws -> String {
        var text = try trimmed(template)
        for (placeholder, file) in sections where text.contains(placeholder) {
            let section = try file.map(trimmed) ?? ""
            text = text.replacingOccurrences(of: placeholder, with: section)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimmed(_ file: PromptFile) throws -> String {
        try read(file).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
