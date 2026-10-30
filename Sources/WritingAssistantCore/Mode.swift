import Foundation

/// The context the author writes in. Each mode has its own channels, language policy, learning
/// summary setting and tone (`prompts/modes/<rawValue>.txt`).
public enum Mode: String, CaseIterable, Codable, Sendable, Identifiable {
    case work
    case personal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .work: "Work"
        case .personal: "Personal"
        }
    }

    /// The other mode, which the mode toggle switches to.
    public var toggled: Mode {
        switch self {
        case .work: .personal
        case .personal: .work
        }
    }
}

/// Which language the polished text is written in. Kotlin's `OutputLanguage` mirrors it.
public enum OutputLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Translate a non-English draft to English first.
    case english
    /// Write in the draft's language; never translate.
    case sameAsInput

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: "English"
        case .sameAsInput: "Same as input"
        }
    }

    /// The prompt file name under `languages/`.
    var fileName: String {
        switch self {
        case .english: "english"
        case .sameAsInput: "same_as_input"
        }
    }
}

/// What a polish request asks for besides the text and the channel.
public struct PolishOptions: Sendable, Equatable {
    public var mode: Mode
    public var outputLanguage: OutputLanguage
    /// Whether to ask for the English learning summary. Even when true, a result only gets one
    /// for English input (see `allowsLearningSummary(detectedLanguage:wasTranslated:)`).
    public var includesLearningSummary: Bool

    public init(mode: Mode, outputLanguage: OutputLanguage, includesLearningSummary: Bool) {
        self.mode = mode
        self.outputLanguage = outputLanguage
        self.includesLearningSummary = includesLearningSummary
    }

    /// Whether a reply with these language fields may carry a learning summary.
    ///
    /// The summary coaches English only. A translation never gets one. Under `.english` an
    /// untranslated draft is English by definition; under `.sameAsInput` the draft can be in any
    /// language, so the reply must name English (a missing language counts as not English).
    public func allowsLearningSummary(detectedLanguage: String?, wasTranslated: Bool) -> Bool {
        guard includesLearningSummary, !wasTranslated else { return false }
        switch outputLanguage {
        case .english: return true
        case .sameAsInput: return Self.isEnglish(detectedLanguage)
        }
    }

    /// True for "English" and variants such as "english" or "English (US)".
    static func isEnglish(_ language: String?) -> Bool {
        guard let language else { return false }
        return language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .hasPrefix("english")
    }
}
