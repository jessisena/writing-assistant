import Foundation
import Testing

@testable import WritingAssistantCore

/// Every preview the scanner returns while reading `chunks` in order.
private func previews(_ chunks: [String]) -> [PolishPreview] {
    var scanner = PolishedTextScanner()
    return chunks.compactMap { scanner.feed($0) }
}

private func polishedTexts(_ chunks: [String]) -> [String] {
    previews(chunks).map(\.polishedText)
}

/// `text` cut at every Unicode scalar boundary into two chunks.
private func everyTwoWaySplit(of text: String) -> [[String]] {
    let scalars = Array(text.unicodeScalars)
    return (0...scalars.count).map { cut in
        [
            String(String.UnicodeScalarView(scalars[..<cut])),
            String(String.UnicodeScalarView(scalars[cut...])),
        ]
    }
}

@Suite struct PolishedTextScannerTests {
    @Test(arguments: [
        #"{"polished_text": "Hi"}"#,
        "```json\n{\"polished_text\": \"Hi\"}\n```",
        "Here is the result:\n```json\n{\n  \"polished_text\" : \"Hi\",\n  \"x\": 1\n}\n```",
        "```\n{\"polished_text\":\"Hi\"}```",
    ])
    func skipsFencesAndPreamble(reply: String) {
        #expect(polishedTexts([reply]) == ["Hi"])
    }

    @Test func decodesEveryJSONEscape() {
        let reply = #"{"polished_text": "q\" b\\ s\/ \b\f\n\r\t end"}"#

        #expect(polishedTexts([reply]) == ["q\" b\\ s/ \u{8}\u{C}\n\r\t end"])
    }

    @Test func decodesUnicodeEscapesAndSurrogatePairs() {
        let reply = #"{"polished_text": "\u00e9 é \uD83D\uDE00 \u00E9 😀 e\u0301"}"#

        #expect(polishedTexts([reply]) == ["é é 😀 é 😀 e\u{301}"])
    }

    @Test func languageFieldsBeforeThePolishedTextAreReported() {
        let reply =
            #"{"detected_language": "Spanish", "was_translated": true, "polished_text": "Hola"}"#

        #expect(
            previews([reply])
                == [
                    PolishPreview(
                        polishedText: "Hola", detectedLanguage: "Spanish", wasTranslated: true)
                ])
    }

    @Test func languageFieldsAfterThePolishedTextAreUnknown() {
        let reply =
            #"{"polished_text": "Hi", "detected_language": "English", "was_translated": false}"#

        #expect(
            previews([reply])
                == [PolishPreview(polishedText: "Hi", detectedLanguage: nil, wasTranslated: nil)])
    }

    @Test func wasTranslatedFalseIsReported() {
        let reply = #"{"was_translated":false,"polished_text":"Hi"}"#

        #expect(previews([reply]).first?.wasTranslated == false)
    }

    @Test(arguments: [#""yes""#, "1", "null", "[]"])
    func nonBooleanWasTranslatedIsUnknown(value: String) {
        let reply = #"{"was_translated": "# + value + #", "polished_text": "Hi"}"#

        #expect(
            previews([reply])
                == [PolishPreview(polishedText: "Hi", detectedLanguage: nil, wasTranslated: nil)])
    }

    @Test func keysInsideNestedValuesAreIgnored() {
        let reply = """
            {"learning_summary": {"polished_text": "nested", "detected_language": "Klingon",
              "corrections": [{"polished_text": "deeper", "was_translated": true}]},
             "list": ["polished_text", {"polished_text": "in array"}],
             "note": "\\"polished_text\\": \\"fake\\"",
             "polished_text": "top"}
            """

        #expect(
            previews([reply])
                == [PolishPreview(polishedText: "top", detectedLanguage: nil, wasTranslated: nil)])
    }

    @Test func aValueSpellingTheKeyIsNotAKey() {
        let reply = #"{"note": "polished_text", "other": "x", "polished_text": "real"}"#

        #expect(polishedTexts([reply]) == ["real"])
    }

    @Test func everyChunkBoundaryYieldsTheSameText() {
        let reply = """
            ```json
            {"detected_language": "Port\\u0075guese", "was_translated": true,
             "polished_text": "a\\"b\\\\c\\/\\n\\uD83D\\uDE00 👍🏽", "learning_summary": null}
            ```
            """
        let expected = PolishPreview(
            polishedText: "a\"b\\c/\n😀 👍🏽", detectedLanguage: "Portuguese", wasTranslated: true)

        for chunks in everyTwoWaySplit(of: reply) {
            #expect(previews(chunks) == [expected], "split: \(chunks)")
        }
        #expect(previews(reply.unicodeScalars.map { String($0) }) == [expected])
    }

    @Test func previewIsReturnedOnlyOnce() {
        let reply = #"{"polished_text": "first"} {"polished_text": "second"}"#

        #expect(polishedTexts([reply]) == ["first"])
        #expect(polishedTexts(reply.map { String($0) }) == ["first"])
    }

    @Test(arguments: [
        "",
        "no json here",
        #"{"polished_text": "never closed"#,
        #"{"polished_text": 42}"#,
        #"{"polished_text": null, "x": "y"}"#,
        #"{"polished_text": "bad escape \x"}"#,
        #"{"polished_text": "lone \uD83D surrogate"}"#,
        #"{"other": "x"} {"polished_text": "after the object"}"#,
        #"{"learning_summary": {"polished_text": "nested only"}}"#,
    ])
    func malformedOrMissingTextYieldsNoPreview(reply: String) {
        #expect(previews([reply]).isEmpty)
    }
}

// MARK: - Property test

/// Pieces random strings are made of: JSON syntax, escapes JSONSerialization must write,
/// combining marks, emoji, and the key names the scanner looks for.
private let stringPieces = [
    "a", " ", "\"", "\\", "\n", "\t", "\r", "/", "{", "}", "[", "]", ":", ",", "é", "e\u{301}",
    "👍🏽", "🇵🇹", "\u{1}", "\u{7F}", "polished_text", "\"polished_text\": \"", "\\u0041", "```",
]

private func randomString(using generator: inout SeededGenerator) -> String {
    (0..<Int.random(in: 0...8, using: &generator))
        .map { _ in stringPieces.randomElement(using: &generator)! }
        .joined()
}

private func serialized(_ value: Any, using generator: inout SeededGenerator) -> String {
    var options: JSONSerialization.WritingOptions = [.fragmentsAllowed]
    if Bool.random(using: &generator) {
        options.insert(.withoutEscapingSlashes)
    }
    if Bool.random(using: &generator) {
        options.insert(.prettyPrinted)
    }
    let data = try! JSONSerialization.data(withJSONObject: value, options: options)
    return String(decoding: data, as: UTF8.self)
}

private func randomSummary(using generator: inout SeededGenerator) -> Any {
    if Int.random(in: 0..<4, using: &generator) == 0 {
        return NSNull()
    }
    return [
        "polished_text": randomString(using: &generator),
        "detected_language": randomString(using: &generator),
        "corrections": [
            [
                "original": randomString(using: &generator),
                "corrected": randomString(using: &generator),
                "why": randomString(using: &generator),
            ]
        ],
        "grammar_insight": randomString(using: &generator),
        "vocabulary": [String](),
    ]
}

/// A random polish reply and the preview the scanner must find in it.
private func randomReply(using generator: inout SeededGenerator) -> (String, PolishPreview) {
    let polished = randomString(using: &generator)
    let language = randomString(using: &generator)
    let translated = Bool.random(using: &generator)
    var entries: [(key: String, value: Any)] = [
        ("polished_text", polished), ("learning_summary", randomSummary(using: &generator)),
    ]
    if Bool.random(using: &generator) {
        entries.append(("detected_language", language))
    }
    if Bool.random(using: &generator) {
        entries.append(("was_translated", translated))
    }
    entries.shuffle(using: &generator)
    let members = entries.map { entry in
        "\"\(entry.key)\":\(serialized(entry.value, using: &generator))"
    }
    let separator = [",", ", ", ",\n  "].randomElement(using: &generator)!
    let fence = ["", "```json\n", "Sure! Here it is:\n```json\n"].randomElement(using: &generator)!
    let reply = "\(fence){\(members.joined(separator: separator))}\(fence.isEmpty ? "" : "\n```")"

    let earlier = Set(entries.prefix { $0.key != "polished_text" }.map(\.key))
    let expected = PolishPreview(
        polishedText: polished,
        detectedLanguage: earlier.contains("detected_language") ? language : nil,
        wasTranslated: earlier.contains("was_translated") ? translated : nil)
    return (reply, expected)
}

/// `text` cut into up to ten chunks at random Unicode scalar boundaries.
private func randomChunks(of text: String, using generator: inout SeededGenerator) -> [String] {
    let scalars = Array(text.unicodeScalars)
    let cutCount = Int.random(in: 0...9, using: &generator)
    let cuts = (0..<cutCount).map { _ in Int.random(in: 0...scalars.count, using: &generator) }
    let bounds = [0] + cuts.sorted() + [scalars.count]
    return zip(bounds, bounds.dropFirst()).map { start, end in
        String(String.UnicodeScalarView(scalars[start..<end]))
    }
}

@Suite struct PolishedTextScannerPropertyTests {
    /// Replies JSONSerialization wrote, in random key order and split at random points, yield
    /// exactly their top-level polished text, once.
    @Test func randomSerializedRepliesYieldTheirPolishedTextOnce() {
        var generator = SeededGenerator(state: 29_102_026)
        for _ in 0..<2_000 {
            let (reply, expected) = randomReply(using: &generator)
            let chunks = randomChunks(of: reply, using: &generator)

            #expect(previews(chunks) == [expected], "reply: \(reply) chunks: \(chunks)")
        }
    }
}
