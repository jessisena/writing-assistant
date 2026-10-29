import Foundation
import Testing
import WritingAssistantCore

/// The style one character carries.
private struct CharacterStyle: Equatable, CustomStringConvertible {
    let character: Character
    let intent: InlinePresentationIntent
    let link: URL?
    let headingLevel: Int?

    var description: String {
        "\(character)[\(intent.rawValue)\(link.map { " \($0)" } ?? "")]"
    }

    /// Whether `other` keeps nothing this style lacks: the round trip may only drop styling.
    func covers(_ other: CharacterStyle) -> Bool {
        character == other.character && headingLevel == other.headingLevel
            && other.intent.isSubset(of: intent) && (other.link == nil || other.link == link)
    }
}

private func characterStyles(of text: AttributedString) -> [CharacterStyle] {
    text.runs.flatMap { run in
        text[run.range].characters.map {
            CharacterStyle(
                character: $0, intent: run.inlinePresentationIntent ?? [], link: run.link,
                headingLevel: run.headingLevel)
        }
    }
}

/// Pieces a run is made of: Markdown characters, emoji, and the starts of bare URLs and email
/// addresses, which must stay plain text.
private let alphabet =
    Array("a .*_#-•`中![~\\👍👍🏽‼️❤️🇵🇹👨‍👩‍👧*️⃣#️⃣©").map(String.init) + ["https://", "www.", "@x.co"]
private let links = [URL(string: "https://a.com/x")!, URL(string: "https://b.com/(y)")!]
private let intentChoices: [InlinePresentationIntent] = [
    .stronglyEmphasized, .emphasized, .strikethrough, .code,
]

private func randomRun(using generator: inout SeededGenerator) -> AttributedString {
    let length = Int.random(in: 1...4, using: &generator)
    var run = AttributedString(
        (0..<length).map { _ in alphabet.randomElement(using: &generator)! }.joined())
    var intent: InlinePresentationIntent = []
    for choice in intentChoices where Int.random(in: 0..<3, using: &generator) == 0 {
        intent.insert(choice)
    }
    run.inlinePresentationIntent = intent.isEmpty ? nil : intent
    if Int.random(in: 0..<4, using: &generator) == 0 {
        run.link = links.randomElement(using: &generator)
    }
    return run
}

/// A line of random runs. With `spaced`, a plain space separates the runs, as between words.
private func randomLine(spaced: Bool, using generator: inout SeededGenerator) -> AttributedString {
    var line = AttributedString()
    for index in 0..<Int.random(in: 1...5, using: &generator) {
        if spaced && index > 0 {
            line += AttributedString(" ")
        }
        line += randomRun(using: &generator)
    }
    if Int.random(in: 0..<6, using: &generator) == 0 {
        line.headingLevel = Int.random(in: 1...3, using: &generator)
    }
    return line
}

private func describe(_ text: AttributedString) -> String {
    text.runs.map { run in
        let characters = String(text[run.range].characters)
        let link = run.link.map { " \($0)" } ?? ""
        return "'\(characters)' \(run.inlinePresentationIntent?.rawValue ?? 0)\(link)"
    }.joined(separator: " | ")
}

/// Checks one Markdown round trip of `line`: every character survives, styling is only ever
/// dropped (whitespace may also take the style of its neighbours), and a second round trip
/// changes nothing. With `wordsKeepStyle`, word characters
/// (neither whitespace nor punctuation) must also keep their style, except inline code inside a
/// link, which Markdown can't express.
private func checkRoundTrip(of line: AttributedString, wordsKeepStyle: Bool) {
    let markdown = RichText.markdown(from: line)
    let reparsed = RichText.attributedString(fromMarkdown: markdown)
    let context = "\(describe(line)) -> \(markdown) -> \(describe(reparsed))"

    let original = characterStyles(of: line)
    let result = characterStyles(of: reparsed)
    #expect(result.count == original.count, "\(context)")
    for (before, after) in zip(original, result) {
        #expect(before.character == after.character, "\(context)")
        if !before.character.isWhitespace {
            #expect(before.covers(after), "\(before) became \(after): \(context)")
        }
        if wordsKeepStyle && isWord(before.character) {
            let expected = before.link == nil ? before.intent : before.intent.subtracting(.code)
            #expect(after.intent == expected, "\(before) became \(after): \(context)")
        }
    }
    let again = RichText.attributedString(fromMarkdown: RichText.markdown(from: reparsed))
    #expect(again == reparsed, "not stable: \(context)")
}

/// Whether `character` is part of a word for CommonMark: emoji and other non-ASCII symbols are.
private func isWord(_ character: Character) -> Bool {
    let isASCIISymbol = character.isASCII && character.isSymbol
    return !character.isWhitespace && !character.isPunctuation && !isASCIISymbol
}

@Suite struct RichTextPropertyTests {
    /// Runs glued together in any combination: Markdown can't express all of them, so only the
    /// documented normalizations may happen.
    @Test func adjacentRunsRoundTripWithOnlyDocumentedLosses() {
        var generator = SeededGenerator(state: 20_261_027)
        for _ in 0..<500 {
            checkRoundTrip(of: randomLine(spaced: false, using: &generator), wordsKeepStyle: false)
        }
    }

    /// Runs separated by spaces, like styled words in a sentence, keep the style of every word.
    @Test func spaceSeparatedRunsKeepTheStyleOfEveryWord() {
        var generator = SeededGenerator(state: 27_102_026)
        for _ in 0..<500 {
            checkRoundTrip(of: randomLine(spaced: true, using: &generator), wordsKeepStyle: true)
        }
    }
}
