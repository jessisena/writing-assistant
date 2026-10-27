import AppKit
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct RichTextBridgeTests {
    private func traits(_ text: NSAttributedString, at index: Int)
        -> NSFontDescriptor.SymbolicTraits
    {
        let font = text.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        return font?.fontDescriptor.symbolicTraits ?? []
    }

    private func editorText(_ markdown: String) -> NSAttributedString {
        RichTextBridge.nsAttributedString(from: RichText.attributedString(fromMarkdown: markdown))
    }

    private func markdown(_ text: NSAttributedString) -> String {
        RichText.markdown(from: RichTextBridge.attributedString(from: text))
    }

    @Test(arguments: [
        "plain text",
        "**bold** and *italic*",
        "***bold italic***",
        "~~gone~~ and `code`",
        "a [link](https://example.com) here",
        "- first\n- second",
        "# Title\nBody",
        "emoji 👩‍👩‍👧 🇪🇸 and 日本語",
        "a literal \\* star",
        "",
    ])
    func markdownSurvivesTheEditor(source: String) {
        #expect(markdown(editorText(source)) == source)
    }

    @Test func intentsBecomeFontTraitsAndAttributes() {
        let text = editorText("**b** *i* ~~s~~ `c` [l](https://example.com)")
        let string = text.string as NSString

        #expect(traits(text, at: string.range(of: "b").location).contains(.bold))
        #expect(traits(text, at: string.range(of: "i").location).contains(.italic))
        #expect(traits(text, at: string.range(of: "c").location).contains(.monoSpace))
        let strike = text.attribute(
            .strikethroughStyle, at: string.range(of: "s").location, effectiveRange: nil)
        #expect(strike as? Int == NSUnderlineStyle.single.rawValue)
        let link = text.attribute(.link, at: string.range(of: "l").location, effectiveRange: nil)
        #expect(link as? URL == URL(string: "https://example.com"))
    }

    @Test func headingUsesALargerBoldFontWithoutCountingAsBold() {
        let text = editorText("## Title")
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        #expect((font?.pointSize ?? 0) > RichTextBridge.bodyFontSize)
        #expect(traits(text, at: 0).contains(.bold))
        let back = RichTextBridge.attributedString(from: text)
        #expect(back.runs.first?.headingLevel == 2)
        #expect(back.runs.first?.inlinePresentationIntent == nil)
    }

    @Test func textUsesTheSystemTextColor() {
        let text = editorText("**hi**")
        let color = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.textColor)
    }

    @Test func normalizingDropsForeignFontsSizesAndColorsButKeepsEmphasis() throws {
        let times = try #require(NSFont(name: "Times New Roman Bold", size: 30))
        let pasted = NSMutableAttributedString(
            string: "Big red",
            attributes: [.font: times, .foregroundColor: NSColor.red]
        )

        let normalized = RichTextBridge.normalized(pasted)

        let font = try #require(normalized.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == RichTextBridge.bodyFontSize)
        #expect(font.familyName != times.familyName)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        let color = normalized.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.textColor)
        #expect(markdown(normalized) == "**Big red**")
    }

    @Test func normalizingHTMLKeepsTheSupportedSubset() throws {
        let html = """
            <p><b>bold</b> <i>italic</i> <s>strike</s> <code>code</code> \
            <a href="https://example.com">link</a> \
            <span style="color: red; font-family: Georgia; font-size: 30px">plain</span></p>
            <ul><li>one</li><li>two</li></ul>
            """
        let pasted = try NSAttributedString(
            data: Data(html.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )

        let result = markdown(RichTextBridge.normalized(pasted))

        #expect(
            result.contains(
                "**bold** *italic* ~~strike~~ `code` [link](https://example.com/) plain"))
        #expect(result.contains("- one\n- two"))
    }

    @Test func normalizingDropsAttachments() {
        let pasted = NSMutableAttributedString(string: "a")
        pasted.append(NSAttributedString(attachment: NSTextAttachment()))
        pasted.append(NSAttributedString(string: "b"))

        #expect(RichTextBridge.normalized(pasted).string == "ab")
    }

    @Test(arguments: ["\t•\tItem", "◦ Item", "\t-\tItem", "• Item"])
    func normalizingTurnsForeignListMarkersIntoBullets(line: String) {
        let normalized = RichTextBridge.normalized(NSAttributedString(string: line))
        #expect(normalized.string == "• Item")
    }

    @Test func normalizingKeepsALeadingHyphenWithASpace() {
        let normalized = RichTextBridge.normalized(NSAttributedString(string: "- not a list"))
        #expect(normalized.string == "- not a list")
    }
}

@MainActor
@Suite struct FormattingTextViewTests {
    private func makeTextView(_ text: String) -> FormattingTextView {
        let textView = FormattingTextView.make()
        textView.setContents(
            NSAttributedString(string: text, attributes: RichTextBridge.baseAttributes))
        return textView
    }

    private func markdown(_ textView: NSTextView) -> String {
        RichText.markdown(from: RichTextBridge.attributedString(from: textView.attributedString()))
    }

    @Test func boldTogglesOnAndOffForTheSelection() {
        let textView = makeTextView("make this bold")
        textView.setSelectedRange(NSRange(location: 10, length: 4))

        textView.toggleBold(nil)
        #expect(markdown(textView) == "make this **bold**")

        textView.toggleBold(nil)
        #expect(markdown(textView) == "make this bold")
    }

    @Test func partlyFormattedSelectionIsFormattedFully() {
        let textView = makeTextView("one two")
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        textView.toggleItalic(nil)
        textView.setSelectedRange(NSRange(location: 0, length: 7))

        textView.toggleItalic(nil)

        #expect(markdown(textView) == "*one two*")
    }

    @Test func strikethroughAndCodeApplyToTheSelection() {
        let textView = makeTextView("old new")
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        textView.toggleStrikethrough(nil)
        textView.setSelectedRange(NSRange(location: 4, length: 3))
        textView.toggleCode(nil)

        #expect(markdown(textView) == "~~old~~ `new`")
    }

    @Test func toggleWithoutSelectionChangesTypingStyle() {
        let textView = makeTextView("")

        textView.toggleBold(nil)

        #expect(RichTextStyle(attributes: textView.typingAttributes).bold)
    }

    @Test func bulletTogglesForEverySelectedParagraph() {
        let textView = makeTextView("one\ntwo\nthree")
        textView.setSelectedRange(NSRange(location: 0, length: 7))

        textView.toggleBullet(nil)
        #expect(textView.string == "• one\n• two\nthree")

        textView.toggleBullet(nil)
        #expect(textView.string == "one\ntwo\nthree")
    }

    @Test(arguments: [
        ("a\n\nb", "• a\n\n• b"),
        ("• a\nb", "• a\n• b"),
        ("• a\n• b", "a\nb"),
        ("", "• "),
    ])
    func togglingBullets(input: String, expected: String) {
        let result = FormattingTextView.togglingBullets(in: NSAttributedString(string: input))
        #expect(result.string == expected)
    }

    @Test func pasteKeepsSupportedFormattingAndDropsForeignFonts() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RichTextBridgeTests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let georgia = try #require(NSFont(name: "Georgia", size: 24))
        let bold = NSFontManager.shared.convert(georgia, toHaveTrait: .boldFontMask)
        let copied = NSMutableAttributedString(string: "pasted ", attributes: [.font: georgia])
        copied.append(NSAttributedString(string: "bold", attributes: [.font: bold]))
        pasteboard.clearContents()
        pasteboard.writeObjects([copied])
        let textView = makeTextView("start ")
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        let pasted = textView.pasteNormalized(from: pasteboard)

        #expect(pasted)
        #expect(markdown(textView) == "start pasted **bold**")
        let font = textView.attributedString().attribute(.font, at: 8, effectiveRange: nil)
        #expect((font as? NSFont)?.pointSize == RichTextBridge.bodyFontSize)
        #expect(textView.selectedRange() == NSRange(location: 17, length: 0))
    }

    @Test func pasteWithoutTextReportsNothingPasted() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RichTextBridgeTests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let textView = makeTextView("keep")

        #expect(!textView.pasteNormalized(from: pasteboard))
        #expect(textView.string == "keep")
    }
}
