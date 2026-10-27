import Foundation

/// Chooses the Claude model for a piece of text.
public enum ModelRouting {
    public static let haikuModel = "claude-haiku-4-5-20251001"
    public static let sonnetModel = "claude-sonnet-5-5"

    static let maxHaikuWords = 60
    static let maxNonASCIIRatio = 0.02
    static let wordPunctuation = CharacterSet(charactersIn: ".,!?;:\"'")

    /// Common Spanish and Portuguese stopwords, used only as a routing hint.
    static let romanceStopwords: Set<String> = [
        "el", "la", "los", "las", "un", "una", "de", "del", "en", "que", "por", "para", "con",
        "su", "sus", "al", "o", "es", "son", "hay", "como", "también", "pero", "si", "no", "yo",
        "lo", "le", "se", "mi", "tu", "da", "do", "em", "com", "não", "mas", "ou", "já",
    ]

    /// Returns the model ID to use for `text`.
    ///
    /// Haiku only when the text is short (at most 60 whitespace-separated words) and
    /// confidently English. Everything else, including ambiguous or empty text, gets Sonnet,
    /// because routing short non-English text to Haiku is the costlier mistake.
    ///
    /// - Parameter text: The user's input text.
    /// - Returns: `haikuModel` or `sonnetModel`.
    public static func pickModel(for text: String) -> String {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        if wordCount <= maxHaikuWords && looksLikeEnglish(text) {
            return haikuModel
        }
        return sonnetModel
    }

    static func looksLikeEnglish(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        if scalars.isEmpty {
            return false
        }
        let nonASCII = scalars.filter { $0.value > 127 }.count
        if Double(nonASCII) / Double(scalars.count) > maxNonASCIIRatio {
            return false
        }
        let romanceHits = text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: wordPunctuation) }
            .filter { romanceStopwords.contains($0) }
            .count
        return romanceHits < 2
    }
}
