import Foundation

/// Locates the JSON object inside a model response.
public enum JSONExtraction {
    /// Returns the JSON object text inside a model response that may have preamble or fencing.
    ///
    /// The model sometimes emits a preamble before the JSON, usually wrapped in a
    /// ```` ```json ```` fence. The first fenced block wins; otherwise the slice from the
    /// first `{` to the last `}` is used; otherwise the trimmed text is returned unchanged.
    ///
    /// - Parameter raw: The model's raw stdout.
    /// - Returns: Text to hand to a JSON parser. It is not validated here.
    public static func extractJSONText(from raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fence = /```(?:json)?\s*(.*?)```/.dotMatchesNewlines()
        if let match = text.firstMatch(of: fence) {
            return String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), end > start {
            return String(text[start...end])
        }
        return text
    }
}
