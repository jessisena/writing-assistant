import Foundation
import Testing
import WritingAssistantCore

private let htmlPrefix = "<meta charset=\"utf-8\">"

private func parse(_ markdown: String) -> AttributedString {
    RichText.attributedString(fromMarkdown: markdown)
}

private func html(_ markdown: String) -> String {
    RichText.html(from: parse(markdown))
}

private func intents(of text: AttributedString) -> [(String, InlinePresentationIntent?)] {
    text.runs.map { (String(text[$0.range].characters), $0.inlinePresentationIntent) }
}

@Suite struct RichTextRoundTripTests {
    @Test(arguments: [
        ("**bold**", "**bold**"),
        ("*italic*", "*italic*"),
        ("***both***", "***both***"),
        ("**bold *both* bold**", "**bold *both* bold**"),
        ("~~strike~~", "~~strike~~"),
        ("`code`", "`code`"),
        ("``a`b``", "``a`b``"),
        ("[link](https://example.com/a)", "[link](https://example.com/a)"),
        ("[link](https://example.com/a(b))", "[link](<https://example.com/a(b)>)"),
        ("**[bold link](https://example.com)**", "**[bold link](https://example.com)**"),
        ("- one\n- **two**", "- one\n- **two**"),
        ("* one", "- one"),
        ("# Title", "# Title"),
        ("### Sub *heading*", "### Sub *heading*"),
        (
            "👨‍👩‍👧 🇵🇹 **ok** 👍🏽",
            "👨‍👩‍👧 🇵🇹 **ok** 👍🏽"
        ),
        ("你好，**世界**", "你好，**世界**"),
        ("", ""),
        ("first\n\nthird", "first\n\nthird"),
        ("**unbalanced", "\\*\\*unbalanced"),
        ("2 * 3 = 6", "2 \\* 3 = 6"),
        ("a &amp; b", "a \\& b"),
        ("\\- not a bullet", "\\- not a bullet"),
        ("\\# not a heading", "\\# not a heading"),
        ("snake_case and ~tilde~", "snake\\_case and ~~tilde~~"),
    ])
    func markdownRoundTrip(input: String, expected: String) {
        let parsed = parse(input)
        let markdown = RichText.markdown(from: parsed)
        #expect(markdown == expected)
        #expect(parse(markdown) == parsed)
    }

    @Test func styledTrailingSpaceMovesOutsideMarkers() {
        var text = AttributedString("hello ")
        text.inlinePresentationIntent = .stronglyEmphasized
        text += AttributedString("world")
        #expect(RichText.markdown(from: text) == "**hello** world")
    }

    @Test func styledWhitespaceOnlyRunIsWrittenUnstyled() {
        var space = AttributedString(" ")
        space.inlinePresentationIntent = .emphasized
        let text = AttributedString("a") + space + AttributedString("b")
        #expect(RichText.markdown(from: text) == "a b")
    }

    @Test func adjacentDifferentLinksStaySeparate() {
        let text = parse("[a](https://a.com)[b](https://b.com)")
        #expect(RichText.markdown(from: text) == "[a](https://a.com)[b](https://b.com)")
    }

    @Test(arguments: [
        (styled("foo.", .stronglyEmphasized) + plain("bar"), "**foo**.bar"),
        (styled("Note:", .stronglyEmphasized) + plain("next"), "**Note**:next"),
        (plain("a") + styled(".b", .emphasized), "a.*b*"),
        (styled("中文。", .stronglyEmphasized) + plain("后面"), "**中文**。后面"),
        (plain("a") + styled("-", .stronglyEmphasized) + plain("b"), "a-b"),
    ])
    func edgePunctuationNextToAWordMovesOutsideMarkers(text: AttributedString, expected: String) {
        let markdown = RichText.markdown(from: text)
        #expect(markdown == expected)
        let reparsed = parse(markdown)
        #expect(String(reparsed.characters) == String(text.characters))
        #expect(parse(RichText.markdown(from: reparsed)) == reparsed)
        let styledWords = intents(of: reparsed).filter { $0.1 != nil }.map(\.0)
        let expectedWords = intents(of: text).filter { $0.1 != nil }.map(\.0).map(wordPart)
        #expect(styledWords == expectedWords.filter { !$0.isEmpty })
    }

    @Test(arguments: ["  ", " ", "   "])
    func allSpaceCodeKeepsItsLength(spaces: String) {
        let text = plain("a") + styled(spaces, .code) + plain("b")
        var current = text
        for _ in 0..<3 {
            current = parse(RichText.markdown(from: current))
        }
        #expect(current == text)
    }

    @Test func headingStartingWithABulletStaysAHeading() {
        var text = AttributedString("• item")
        text.headingLevel = 2
        let markdown = RichText.markdown(from: text)
        #expect(markdown == "## • item")
        #expect(parse(markdown) == text)
    }

    @Test func exclamationMarkBeforeALinkIsNotAnImage() {
        var link = AttributedString("a")
        link.link = URL(string: "https://x.com")
        let text = plain("!") + link
        let markdown = RichText.markdown(from: text)
        #expect(markdown == "\\![a](https://x.com)")
        #expect(parse(markdown) == text)
    }
}

private func plain(_ text: String) -> AttributedString {
    AttributedString(text)
}

private func styled(_ text: String, _ intent: InlinePresentationIntent) -> AttributedString {
    var result = AttributedString(text)
    result.inlinePresentationIntent = intent
    return result
}

/// The run text without edge punctuation, which is expected to lose its style.
private func wordPart(_ text: String) -> String {
    String(text.drop(while: \.isPunctuation).reversed().drop(while: \.isPunctuation).reversed())
}

@Suite struct RichTextParsingTests {
    @Test func boldItalicStrikeAndCodeMapToIntents() {
        let runs = intents(of: parse("**b** *i* ~~s~~ `c` ***bi***"))
        let styled = runs.filter { $0.1 != nil }
        #expect(styled.map(\.0) == ["b", "i", "s", "c", "bi"])
        #expect(
            styled.map(\.1) == [
                .stronglyEmphasized, .emphasized, .strikethrough, .code,
                [.stronglyEmphasized, .emphasized],
            ])
    }

    @Test func linkSetsLinkAttribute() {
        let text = parse("see [docs](https://example.com)")
        let link = text.runs.compactMap(\.link).first
        #expect(link == URL(string: "https://example.com"))
        #expect(String(text.characters) == "see docs")
    }

    @Test func bulletLinesGetBulletPrefix() {
        let text = parse("- one\n* two\n-not a bullet")
        #expect(String(text.characters) == "• one\n• two\n-not a bullet")
    }

    @Test func headingLevelIsStoredAsAttribute() {
        let text = parse("## Title\nbody")
        let levels = text.runs.map { ($0.headingLevel, String(text[$0.range].characters)) }
        #expect(levels.first?.0 == 2)
        #expect(levels.first?.1 == "Title")
        #expect(levels.last?.0 == nil)
        #expect(String(text.characters) == "Title\nbody")
    }

    @Test func hashWithoutSpaceIsNotAHeading() {
        let text = parse("#tag and ####### seven")
        #expect(text.runs.allSatisfy { $0.headingLevel == nil })
        #expect(String(text.characters) == "#tag and ####### seven")
    }

    @Test func inlineHTMLStaysLiteralWithoutFormatting() {
        let text = parse("<b>hi</b>")
        #expect(String(text.characters) == "<b>hi</b>")
        #expect(text.runs.allSatisfy { $0.inlinePresentationIntent == nil })
    }

    @Test func imageStaysLiteralWithItsURL() {
        let text = parse("see ![alt](https://x.com/a.png) now")
        #expect(String(text.characters) == "see ![alt](https://x.com/a.png) now")
        #expect(text.runs.allSatisfy { $0.link == nil && $0.imageURL == nil })
        let reparsed = parse(RichText.markdown(from: text))
        #expect(String(reparsed.characters) == String(text.characters))
    }

    @Test func imageInsideCodeStaysCode() {
        let text = parse("`![a](b)`")
        #expect(intents(of: text).map(\.0) == ["![a](b)"])
        #expect(intents(of: text).map(\.1) == [.code])
    }

    @Test func carriageReturnLineEndingsSplitLines() {
        let text = parse("- a\r\n- b")
        #expect(String(text.characters) == "• a\n• b")
    }

    @Test func emptyStringGivesEmptyText() {
        #expect(parse("").characters.isEmpty)
    }
}

@Suite struct RichTextHTMLTests {
    @Test func inlineFormattingUsesTags() {
        #expect(
            html("**b** *i* ~~s~~ `c`")
                == htmlPrefix + "<b>b</b> <i>i</i> <s>s</s> <code>c</code>")
    }

    @Test func nestedFormattingNestsTags() {
        #expect(html("***x***") == htmlPrefix + "<b><i>x</i></b>")
    }

    @Test func scriptTagIsEscaped() {
        #expect(
            html("<script>alert('x')</script>")
                == htmlPrefix + "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;")
    }

    @Test func ampersandAndQuotesAreEscaped() {
        #expect(html("a & b \"c\"") == htmlPrefix + "a &amp; b &quot;c&quot;")
    }

    @Test func linkHrefIsEscaped() {
        let result = html("[x](https://e.com/?a=1&b='2')")
        #expect(result == htmlPrefix + "<a href=\"https://e.com/?a=1&amp;b=&#39;2&#39;\">x</a>")
    }

    @Test func unsafeLinkSchemeBecomesPlainText() {
        #expect(html("[x](javascript:alert(1))") == htmlPrefix + "x")
    }

    @Test func consecutiveBulletsShareOneList() {
        #expect(
            html("- a\n- **b**\ntext\n- c")
                == htmlPrefix + "<ul><li>a</li><li><b>b</b></li></ul>text<ul><li>c</li></ul>")
    }

    @Test func headingBecomesBoldParagraph() {
        #expect(html("# Title\nbody") == htmlPrefix + "<p><b>Title</b></p>body")
    }

    @Test func lineBreaksBecomeBreakTags() {
        #expect(html("a\nb\n\nc") == htmlPrefix + "a<br>b<br><br>c")
    }

    @Test func emojiPassThrough() {
        #expect(html("👨‍👩‍👧 🇵🇹") == htmlPrefix + "👨‍👩‍👧 🇵🇹")
    }

    @Test func emptyTextGivesOnlyPrefix() {
        #expect(html("") == htmlPrefix)
    }
}

@Suite struct RichTextPlainTextTests {
    @Test func markersAreRemovedAndBulletsKept() {
        let text = parse("**Hi** *there* [link](https://x.com)\n- a\n# Title\n`code` ~~old~~")
        #expect(RichText.plainText(from: text) == "Hi there link\n• a\nTitle\ncode old")
    }

    @Test func emptyTextGivesEmptyString() {
        #expect(RichText.plainText(from: AttributedString()) == "")
    }

    @Test func plainTextLeavesLinkTargetsOut() {
        #expect(RichText.plainText(from: parse("[docs](https://x.com)")) == "docs")
    }

    @Test(arguments: [
        ("see [the **docs**](https://x.com/a) now", "see the docs (https://x.com/a) now"),
        ("[https://x.com](https://x.com)", "https://x.com"),
        ("mail [me@x.com](mailto:me@x.com)", "mail me@x.com"),
        ("[write](mailto:me@x.com)", "write (mailto:me@x.com)"),
        ("[a](https://a.com) and [b](https://b.com)", "a (https://a.com) and b (https://b.com)"),
        ("[run](javascript:void)", "run"),
        ("- **Hi** [x](https://x.com)\n# Title", "• Hi x (https://x.com)\nTitle"),
        ("", ""),
    ])
    func clipboardTextAddsLinkTargets(markdown: String, expected: String) {
        #expect(RichText.clipboardText(from: parse(markdown)) == expected)
    }
}
