import Foundation
import Testing

@testable import WritingAssistantCore

/// Every preview the scanner returns while reading `chunks` in order.
private func previews(_ chunks: [String]) -> [PolishPreview] {
    var scanner = PolishedTextScanner()
    return chunks.compactMap { scanner.feed($0) }
}

/// The texts of the previews that report the polished text complete.
private func completeTexts(_ chunks: [String]) -> [String] {
    previews(chunks).filter(\.isTextComplete).compactMap(\.polishedText)
}

private func isScalarPrefix(_ prefix: String, of text: String) -> Bool {
    text.unicodeScalars.starts(with: prefix.unicodeScalars)
}

/// Checks the previews for `chunks`: the last one is `expected`, every text on the way is a
/// prefix of the final text (so no half escape ever shows), each update changes something, and
/// no text other than the final one is ever reported complete.
private func expectStream(
    _ chunks: [String], endsWith expected: PolishPreview,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let stream = previews(chunks)
    #expect(stream.last == expected, "chunks: \(chunks)", sourceLocation: sourceLocation)
    let finalText = expected.polishedText ?? ""
    for (index, preview) in stream.enumerated() {
        let text = preview.polishedText ?? ""
        #expect(isScalarPrefix(text, of: finalText), "\(text)", sourceLocation: sourceLocation)
        if index > 0 {
            #expect(preview != stream[index - 1], sourceLocation: sourceLocation)
        }
    }
    let completes = Set(stream.filter(\.isTextComplete).compactMap(\.polishedText))
    #expect(
        completes == (expected.isTextComplete ? [finalText] : []), sourceLocation: sourceLocation)
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

private func scalarChunks(_ text: String) -> [String] {
    text.unicodeScalars.map { String($0) }
}

private func complete(
    _ text: String, language: String? = nil, translated: Bool? = nil
) -> PolishPreview {
    PolishPreview(
        polishedText: text, isTextComplete: true, detectedLanguage: language,
        wasTranslated: translated)
}

@Suite struct PolishedTextScannerTests {
    @Test(arguments: [
        #"{"polished_text": "Hi"}"#,
        "```json\n{\"polished_text\": \"Hi\"}\n```",
        "Here is the result:\n```json\n{\n  \"polished_text\" : \"Hi\",\n  \"x\": 1\n}\n```",
        "```\n{\"polished_text\":\"Hi\"}```",
    ])
    func skipsFencesAndPreamble(reply: String) {
        #expect(completeTexts([reply]) == ["Hi"])
        #expect(completeTexts(scalarChunks(reply)) == ["Hi"])
    }

    @Test func decodesEveryJSONEscape() {
        let reply = #"{"polished_text": "q\" b\\ s\/ \b\f\n\r\t end"}"#

        #expect(completeTexts([reply]) == ["q\" b\\ s/ \u{8}\u{C}\n\r\t end"])
    }

    @Test func decodesUnicodeEscapesAndSurrogatePairs() {
        let reply = #"{"polished_text": "\u00e9 é \uD83D\uDE00 \u00E9 😀 e\u0301"}"#

        #expect(completeTexts([reply]) == ["é é 😀 é 😀 e\u{301}"])
    }

    @Test func textGrowsScalarByScalarFromAnEmptyString() {
        let reply = #"{"polished_text": "Hi \u00e9!"}"#

        let stream = previews(scalarChunks(reply))

        #expect(stream.map(\.polishedText) == ["", "H", "Hi", "Hi ", "Hi é", "Hi é!", "Hi é!"])
        #expect(stream.map(\.isTextComplete) == [false, false, false, false, false, false, true])
    }

    @Test func partialTextHoldsBackAnIncompleteEscape() {
        var scanner = PolishedTextScanner()

        let first = scanner.feed(#"{"polished_text": "a\uD83D\uDE"#)
        let second = scanner.feed(#"80b\"#)
        let third = scanner.feed(#"nc"#)

        #expect(first == PolishPreview(polishedText: "a"))
        #expect(second == PolishPreview(polishedText: "a🚀b"))
        #expect(third == PolishPreview(polishedText: "a🚀b\nc"))
    }

    @Test func chunkThatChangesNothingReturnsNil() {
        var scanner = PolishedTextScanner()
        let known = PolishPreview(detectedLanguage: "Spanish", wasTranslated: true)
        var started = known
        started.polishedText = ""

        #expect(scanner.feed("```json\n{\"detected_") == nil)
        #expect(scanner.feed("language\": \"Span") == nil)
        #expect(scanner.feed("ish\",") == PolishPreview(detectedLanguage: "Spanish"))
        #expect(scanner.feed(" \"was_translated\": tr") == nil)
        #expect(scanner.feed("ue, ") == known)
        #expect(scanner.feed("\"polished_text\": \"\\") == started)
        #expect(scanner.feed("u00") == nil)
    }

    @Test func languageFieldsBeforeThePolishedTextAreReportedWithIt() {
        let reply =
            #"{"detected_language": "Spanish", "was_translated": true, "polished_text": "Hola"}"#

        expectStream(
            scalarChunks(reply), endsWith: complete("Hola", language: "Spanish", translated: true))
        #expect(previews([reply]) == [complete("Hola", language: "Spanish", translated: true)])
    }

    @Test func languageFieldsAfterThePolishedTextFollowIt() {
        var scanner = PolishedTextScanner()

        let text = scanner.feed(#"{"polished_text": "Hi","#)
        let language = scanner.feed(#" "detected_language": "English","#)
        let translated = scanner.feed(#" "was_translated": false}"#)

        #expect(text == complete("Hi"))
        #expect(language == complete("Hi", language: "English"))
        #expect(translated == complete("Hi", language: "English", translated: false))
    }

    @Test func wasTranslatedFalseIsReported() {
        let reply = #"{"was_translated":false,"polished_text":"Hi"}"#

        #expect(previews([reply]).last?.wasTranslated == false)
    }

    @Test(arguments: [#""yes""#, "1", "null", "[]"])
    func nonBooleanWasTranslatedIsUnknown(value: String) {
        let reply = #"{"was_translated": "# + value + #", "polished_text": "Hi"}"#

        #expect(previews([reply]) == [complete("Hi")])
    }

    @Test func keysInsideNestedValuesAreIgnored() {
        let reply = """
            {"learning_summary": {"polished_text": "nested", "detected_language": "Klingon",
              "corrections": [{"polished_text": "deeper", "was_translated": true}]},
             "list": ["polished_text", {"polished_text": "in array"}],
             "note": "\\"polished_text\\": \\"fake\\"",
             "polished_text": "top"}
            """

        #expect(previews([reply]) == [complete("top")])
        expectStream(scalarChunks(reply), endsWith: complete("top"))
    }

    @Test func aValueSpellingTheKeyIsNotAKey() {
        let reply = #"{"note": "polished_text", "other": "x", "polished_text": "real"}"#

        #expect(completeTexts([reply]) == ["real"])
    }

    @Test func everyChunkBoundaryYieldsTheSameStream() {
        let reply = """
            ```json
            {"detected_language": "Port\\u0075guese", "was_translated": true,
             "polished_text": "a\\"b\\\\c\\/\\n\\u00e9\\uD83D\\uDE80 👍🏽 e\u{301}",
             "learning_summary": null}
            ```
            """
        let expected = complete(
            "a\"b\\c/\né🚀 👍🏽 e\u{301}", language: "Portuguese", translated: true)

        for chunks in everyTwoWaySplit(of: reply) {
            expectStream(chunks, endsWith: expected)
        }
        expectStream(scalarChunks(reply), endsWith: expected)
    }

    @Test func everyChunkBoundaryOfAReplyWithTheTextFirstYieldsTheSameStream() {
        let reply =
            #"{"polished_text":"x\u00e9\\","detected_language":"French","was_translated":true}"#
        let expected = complete("xé\\", language: "French", translated: true)

        for chunks in everyTwoWaySplit(of: reply) {
            expectStream(chunks, endsWith: expected)
        }
    }

    @Test func nothingIsReportedAfterTheObjectCloses() {
        let reply = #"{"polished_text": "first"} {"polished_text": "x", "was_translated": true}"#

        #expect(previews([reply]).last == complete("first"))
        #expect(previews(scalarChunks(reply)).last == complete("first"))
    }

    @Test func aRepeatedPolishedTextKeyDoesNotReplaceTheText() {
        let reply = #"{"polished_text": "first", "polished_text": "second"}"#

        expectStream(scalarChunks(reply), endsWith: complete("first"))
    }

    @Test(arguments: [
        "",
        "no json here",
        #"{"polished_text": "never closed"#,
        #"{"polished_text": 42}"#,
        #"{"polished_text": null, "x": "y"}"#,
        #"{"polished_text": "bad escape \x"}"#,
        #"{"polished_text": "bad hex \u00G1"}"#,
        #"{"polished_text": "lone \uD83D surrogate"}"#,
        #"{"polished_text": "two highs \uD83D\uD83D"}"#,
        #"{"polished_text": "high then other escape \uD83D\n"}"#,
        #"{"polished_text": "lone low \uDE80"}"#,
        #"{"polished_text": "high then quote \uD83D"}"#,
        "{\"polished_text\": \"raw\nnewline\"}",
        #"{"other": "x"} {"polished_text": "after the object"}"#,
        #"{"learning_summary": {"polished_text": "nested only"}}"#,
    ])
    func malformedOrMissingTextIsNeverComplete(reply: String) {
        #expect(completeTexts([reply]).isEmpty)
        #expect(completeTexts(scalarChunks(reply)).isEmpty)
    }

    @Test func malformedTextStopsTheScan() {
        var scanner = PolishedTextScanner()

        #expect(scanner.feed(#"{"polished_text": "ok \q"#) == PolishPreview(polishedText: "ok "))
        #expect(scanner.feed(#"more", "detected_language": "English"}"#) == nil)
    }
}

// MARK: - Property test

/// Pieces random strings are made of: JSON syntax, escapes JSONSerialization must write,
/// combining marks, emoji, and the key names the scanner looks for.
private let stringPieces = [
    "a", " ", "\"", "\\", "\n", "\t", "\r", "/", "{", "}", "[", "]", ":", ",", "é", "e\u{301}",
    "👍🏽", "🇵🇹", "🚀", "\u{1}", "\u{7F}", "polished_text", "\"polished_text\": \"", "\\u0041",
    "```",
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

/// `text` with every scalar outside ASCII written as `\uXXXX` escapes (surrogate pairs above
/// the BMP), the way some JSON writers do. Only valid for the inside of JSON strings.
private func asciiEscaped(_ text: String) -> String {
    text.utf16.map { unit in
        unit < 0x80
            ? String(UnicodeScalar(UInt8(unit))) : String(format: "\\u%04X", unit)
    }.joined()
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

/// A random polish reply and the last preview the scanner must report for it.
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
    let escapesAll = Int.random(in: 0..<4, using: &generator) == 0
    let members = entries.map { entry in
        let value = serialized(entry.value, using: &generator)
        return "\"\(entry.key)\":\(escapesAll ? asciiEscaped(value) : value)"
    }
    let separator = [",", ", ", ",\n  "].randomElement(using: &generator)!
    let fence = ["", "```json\n", "Sure! Here it is:\n```json\n"].randomElement(using: &generator)!
    let reply = "\(fence){\(members.joined(separator: separator))}\(fence.isEmpty ? "" : "\n```")"

    let keys = Set(entries.map(\.key))
    let expected = PolishPreview(
        polishedText: polished, isTextComplete: true,
        detectedLanguage: keys.contains("detected_language") ? language : nil,
        wasTranslated: keys.contains("was_translated") ? translated : nil)
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
    /// Replies JSONSerialization wrote, in random key order, sometimes with every non-ASCII
    /// character escaped, and split at random points, end with exactly their top-level fields,
    /// and every text on the way is a prefix of the final one.
    @Test func randomSerializedRepliesStreamTheirTopLevelFields() {
        var generator = SeededGenerator(state: 29_102_026)
        for _ in 0..<2_000 {
            let (reply, expected) = randomReply(using: &generator)
            let chunks = randomChunks(of: reply, using: &generator)

            expectStream(chunks, endsWith: expected)
        }
    }
}
