import WritingAssistantCore

/// What a running polish is doing, as far as its streamed reply tells, for the status line.
enum PolishStage: Equatable {
    /// Nothing about the language yet: the reply starts with `detected_language`.
    case detectingLanguage
    /// The reply said it translates; the language is nil when it didn't name it first.
    case translating(from: String?)
    /// The polished text is coming and isn't a translation (or the reply didn't say yet).
    case polishing
    /// The polished text is complete and the learning summary is coming.
    case writingTips
    /// The polished text is complete and no summary is coming: the reply is ending.
    case finishing

    /// The stage `preview` shows. A reply that writes `polished_text` before its language
    /// fields reads as `.polishing`, never as a guessed language.
    ///
    /// - Parameters:
    ///   - preview: What the reply has said so far; nil before it said anything.
    ///   - includesLearningSummary: Whether the request asked for a summary. A translation never
    ///     gets one.
    init(_ preview: PolishPreview?, includesLearningSummary: Bool) {
        guard let preview, preview.wasTranslated != nil || preview.polishedText != nil else {
            self = .detectingLanguage
            return
        }
        if preview.isTextComplete {
            let expectsSummary = includesLearningSummary && preview.wasTranslated != true
            self = expectsSummary ? .writingTips : .finishing
        } else if preview.wasTranslated == true {
            self = .translating(from: preview.detectedLanguage)
        } else {
            self = .polishing
        }
    }

    var label: String {
        switch self {
        case .detectingLanguage: "Detecting language…"
        case .translating(let language?): "Translating from \(language)…"
        case .translating(nil): "Translating…"
        case .polishing: "Polishing…"
        case .writingTips: "Writing tips…"
        case .finishing: "Finishing…"
        }
    }
}
