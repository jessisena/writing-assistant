import Foundation

/// Finds the top-level `polished_text` of a polish reply while the reply is still streaming.
///
/// Feed it the reply text piece by piece. It ignores everything before the first `{` (the model
/// often wraps the JSON in a ```` ```json ```` fence), follows nesting and string state, and
/// returns a preview as soon as the top-level `polished_text` string closes. Keys inside nested
/// objects, such as a `polished_text` inside `learning_summary`, are ignored. Malformed input
/// never yields a preview.
struct PolishedTextScanner: Sendable {
    private var depth = 0
    private var isInString = false
    private var isEscaping = false
    /// Whether the next top-level string is a key rather than a value.
    private var expectsKey = true
    private var key: String?
    /// A top-level string being read, quotes and escapes included.
    private var literal = ""
    /// A top-level value that isn't a string or container, such as `true`.
    private var bareValue = ""
    private var detectedLanguage: String?
    private var wasTranslated: Bool?
    private var isFinished = false

    init() {}

    /// Reads the next piece of the reply.
    ///
    /// - Parameter chunk: Text that directly follows every chunk fed before.
    /// - Returns: The preview, exactly once: from the call that completes `polished_text`.
    mutating func feed(_ chunk: String) -> PolishPreview? {
        for scalar in chunk.unicodeScalars where !isFinished {
            if let preview = consume(scalar) {
                isFinished = true
                return preview
            }
        }
        return nil
    }

    private mutating func consume(_ scalar: Unicode.Scalar) -> PolishPreview? {
        if isInString {
            return consumeInString(scalar)
        }
        if depth == 0 {
            if scalar == "{" {
                depth = 1
            }
            return nil
        }
        consumeStructure(scalar)
        return nil
    }

    private mutating func consumeInString(_ scalar: Unicode.Scalar) -> PolishPreview? {
        if depth == 1 {
            literal.unicodeScalars.append(scalar)
        }
        if isEscaping {
            isEscaping = false
        } else if scalar == "\\" {
            isEscaping = true
        } else if scalar == "\"" {
            isInString = false
            return depth == 1 ? finishTopLevelString() : nil
        }
        return nil
    }

    private mutating func consumeStructure(_ scalar: Unicode.Scalar) {
        switch scalar {
        case "\"":
            isInString = true
            literal = depth == 1 ? "\"" : ""
        case "{", "[":
            depth += 1
        case "}", "]":
            depth -= 1
            if depth == 0 {
                finishBareValue()
                isFinished = true
            }
        case ":" where depth == 1:
            expectsKey = false
        case "," where depth == 1:
            finishBareValue()
            expectsKey = true
            key = nil
        default:
            if depth == 1 && !expectsKey && !scalar.properties.isWhitespace {
                bareValue.unicodeScalars.append(scalar)
            }
        }
    }

    private mutating func finishTopLevelString() -> PolishPreview? {
        let value = Self.decode(literal)
        literal = ""
        if expectsKey {
            key = value
            return nil
        }
        switch key {
        case "polished_text":
            guard let value else {
                isFinished = true
                return nil
            }
            return PolishPreview(
                polishedText: value, detectedLanguage: detectedLanguage,
                wasTranslated: wasTranslated)
        case "detected_language":
            detectedLanguage = value
        default:
            break
        }
        return nil
    }

    private mutating func finishBareValue() {
        if key == "was_translated" {
            switch bareValue {
            case "true": wasTranslated = true
            case "false": wasTranslated = false
            default: break
            }
        }
        bareValue = ""
    }

    /// Decodes a quoted JSON string literal with full JSON escape semantics.
    private static func decode(_ literal: String) -> String? {
        let parsed = try? JSONSerialization.jsonObject(
            with: Data(literal.utf8), options: .fragmentsAllowed)
        return parsed as? String
    }
}
