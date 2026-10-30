import Foundation

/// Builds the system prompts from the prompt files. Kotlin's `PromptAssembler` mirrors this.
///
/// Each template's placeholders are replaced by the trimmed section files they name. A section
/// file is only read when its placeholder is in the template, so a `polish.txt` edited before a
/// section existed keeps working unchanged: it simply has nothing to fill.
extension PromptStoring {
    /// The polish prompt for `channel` under `options`.
    ///
    /// `polish.txt` with the shared rules, the language policy for `options.outputLanguage`, the
    /// tone of `options.mode`, the channel guidelines and, only when
    /// `options.includesLearningSummary` is true, the learning summary section. When it is false
    /// the placeholder is removed, so the prompt carries no summary instructions at all.
    ///
    /// - Throws: `PromptStoreError` when a needed prompt file couldn't be read.
    public func assemble(for channel: Channel, options: PolishOptions) throws -> String {
        try fill(
            .global,
            [
                (PromptFile.alwaysPlaceholder, .always),
                (PromptFile.languagePolicyPlaceholder, .languagePolicy(options.outputLanguage)),
                (PromptFile.modePlaceholder, .mode(options.mode)),
                (PromptFile.channelPlaceholder, .channel(channel)),
                (
                    PromptFile.learningSummaryPlaceholder,
                    options.includesLearningSummary ? .learningSummary : nil
                ),
            ])
    }

    /// The refine prompt: `refine.txt` with the shared rules, the channel guidelines and the
    /// instruction, which is a preset's refinement file or the user's own text.
    ///
    /// Custom text is inserted last and without the prompt placeholders it contains (see
    /// `RefinementInstruction.validated()`), so it can't pull another section in.
    ///
    /// - Throws: `PromptStoreError` when a needed prompt file couldn't be read.
    public func assembleRefinement(
        _ instruction: RefinementInstruction, for channel: Channel
    ) throws -> String {
        let shared: [(placeholder: String, file: PromptFile?)] = [
            (PromptFile.alwaysPlaceholder, .always),
            (PromptFile.channelPlaceholder, .channel(channel)),
        ]
        switch instruction {
        case .preset(let refinement):
            return try fill(
                .refine, shared + [(PromptFile.instructionPlaceholder, .refinement(refinement))])
        case .custom(let text):
            return try fill(.refine, shared).replacingOccurrences(
                of: PromptFile.instructionPlaceholder,
                with: RefinementInstruction.withoutPlaceholders(text))
        }
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
