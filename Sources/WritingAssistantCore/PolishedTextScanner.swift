import Foundation

/// Follows a polish reply while it is still streaming and reports what it has said so far.
///
/// Feed it the reply text piece by piece. It ignores everything before the first `{` (the model
/// often wraps the JSON in a ```` ```json ```` fence) and follows nesting and string state. The
/// top-level `polished_text` is decoded as it arrives, so the preview grows with the reply; an
/// escape (`\"`, `\n`, `\u00e9`, the two halves of a `\uD83D\uDE80` pair) is only added once it is
/// complete. `detected_language` and `was_translated` are reported once their values end, before
/// or after the text. Keys inside nested objects, such as a `polished_text` inside
/// `learning_summary`, are ignored. Scanning stops when the top-level object closes, or at the
/// first malformed top-level string, which therefore never yields a complete text.
struct PolishedTextScanner: Sendable {
    private var depth = 0
    private var isInString = false
    /// Whether the previous scalar of a nested string was an unescaped backslash.
    private var isEscaping = false
    /// Whether the next top-level string is a key rather than a value.
    private var expectsKey = true
    private var key: String?
    /// The top-level string being read.
    private var string = JSONStringDecoder()
    /// A top-level value that isn't a string or container, such as `true`.
    private var bareValue = ""
    private var preview = PolishPreview()
    private var hasChanged = false
    private var isFinished = false

    init() {}

    /// Reads the next piece of the reply.
    ///
    /// - Parameter chunk: Text that directly follows every chunk fed before.
    /// - Returns: What the reply has said so far, when this chunk changed it; otherwise nil.
    mutating func feed(_ chunk: String) -> PolishPreview? {
        for scalar in chunk.unicodeScalars where !isFinished {
            consume(scalar)
        }
        guard hasChanged else { return nil }
        hasChanged = false
        return preview
    }

    private mutating func consume(_ scalar: Unicode.Scalar) {
        if isInString {
            if depth == 1 {
                consumeTopLevelString(scalar)
            } else {
                consumeNestedString(scalar)
            }
        } else if depth == 0 {
            if scalar == "{" {
                depth = 1
            }
        } else {
            consumeStructure(scalar)
        }
    }

    private mutating func consumeTopLevelString(_ scalar: Unicode.Scalar) {
        let step = string.consume(scalar)
        let isPolishedText = !expectsKey && key == "polished_text" && !preview.isTextComplete
        switch step {
        case .malformed:
            isFinished = true
        case .closed:
            isInString = false
            finishTopLevelString()
        case .decoded where isPolishedText:
            preview.polishedText = string.decoded
            hasChanged = true
        case .decoded, .pending:
            break
        }
    }

    private mutating func consumeNestedString(_ scalar: Unicode.Scalar) {
        if isEscaping {
            isEscaping = false
        } else if scalar == "\\" {
            isEscaping = true
        } else if scalar == "\"" {
            isInString = false
        }
    }

    private mutating func consumeStructure(_ scalar: Unicode.Scalar) {
        switch scalar {
        case "\"":
            isInString = true
            string = JSONStringDecoder()
            startPolishedTextIfNeeded()
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

    /// Reports an empty text as soon as the first top-level `polished_text` string opens.
    private mutating func startPolishedTextIfNeeded() {
        guard depth == 1, !expectsKey, key == "polished_text", preview.polishedText == nil else {
            return
        }
        preview.polishedText = ""
        hasChanged = true
    }

    private mutating func finishTopLevelString() {
        let value = string.decoded
        if expectsKey {
            key = value
            return
        }
        switch key {
        case "polished_text" where !preview.isTextComplete:
            preview.polishedText = value
            preview.isTextComplete = true
            hasChanged = true
        case "detected_language" where preview.detectedLanguage != value:
            preview.detectedLanguage = value
            hasChanged = true
        default:
            break
        }
    }

    private mutating func finishBareValue() {
        if key == "was_translated" {
            let value: Bool? =
                switch bareValue {
                case "true": true
                case "false": false
                default: nil
                }
            if let value, value != preview.wasTranslated {
                preview.wasTranslated = value
                hasChanged = true
            }
        }
        bareValue = ""
    }
}

/// Decodes the body of a JSON string one Unicode scalar at a time, after its opening quote, with
/// the same rules as `JSONSerialization`: raw control characters, unknown escapes and unpaired
/// surrogates are malformed.
struct JSONStringDecoder: Sendable {
    enum Step: Equatable {
        /// The scalar completed a character, which `decoded` now ends with.
        case decoded
        /// The scalar is part of an escape that isn't complete yet.
        case pending
        /// The scalar is the closing quote.
        case closed
        case malformed
    }

    private enum Escape {
        case none
        case afterBackslash
        case unicode(digits: String)
    }

    private static let simpleEscapes: [Unicode.Scalar: Unicode.Scalar] = [
        "\"": "\"", "\\": "\\", "/": "/", "b": "\u{8}", "f": "\u{C}", "n": "\n", "r": "\r",
        "t": "\t",
    ]

    /// Every complete character so far.
    private(set) var decoded = ""
    private var escape = Escape.none
    /// The first half of a surrogate pair (`\uD83D` of `\uD83D\uDE80`), waiting for the second.
    private var highSurrogate: UInt32?

    mutating func consume(_ scalar: Unicode.Scalar) -> Step {
        switch escape {
        case .afterBackslash:
            return consumeEscapeLetter(scalar)
        case .unicode(let digits):
            return consumeHexDigit(scalar, after: digits)
        case .none:
            break
        }
        if scalar == "\\" {
            escape = .afterBackslash
            return .pending
        }
        guard highSurrogate == nil, scalar.value >= 0x20 else { return .malformed }
        if scalar == "\"" {
            return .closed
        }
        decoded.unicodeScalars.append(scalar)
        return .decoded
    }

    private mutating func consumeEscapeLetter(_ scalar: Unicode.Scalar) -> Step {
        if scalar == "u" {
            escape = .unicode(digits: "")
            return .pending
        }
        guard highSurrogate == nil, let unescaped = Self.simpleEscapes[scalar] else {
            return .malformed
        }
        escape = .none
        decoded.unicodeScalars.append(unescaped)
        return .decoded
    }

    private mutating func consumeHexDigit(_ scalar: Unicode.Scalar, after digits: String) -> Step {
        guard scalar.properties.isASCIIHexDigit else { return .malformed }
        let digits = digits + String(scalar)
        guard digits.count == 4, let unit = UInt32(digits, radix: 16) else {
            escape = .unicode(digits: digits)
            return .pending
        }
        escape = .none
        return append(codeUnit: unit)
    }

    private mutating func append(codeUnit unit: UInt32) -> Step {
        var value = unit
        switch unit {
        case 0xD800...0xDBFF:
            guard highSurrogate == nil else { return .malformed }
            highSurrogate = unit
            return .pending
        case 0xDC00...0xDFFF:
            guard let high = highSurrogate else { return .malformed }
            highSurrogate = nil
            value = 0x10000 + ((high - 0xD800) << 10) + (unit - 0xDC00)
        default:
            guard highSurrogate == nil else { return .malformed }
        }
        guard let scalar = Unicode.Scalar(value) else { return .malformed }
        decoded.unicodeScalars.append(scalar)
        return .decoded
    }
}
