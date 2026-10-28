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

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RichTextBridgeTests-\(UUID())"))
        pasteboard.clearContents()
        return pasteboard
    }

    private func georgiaText() throws -> NSAttributedString {
        let georgia = try #require(NSFont(name: "Georgia", size: 24))
        let bold = NSFontManager.shared.convert(georgia, toHaveTrait: .boldFontMask)
        let copied = NSMutableAttributedString(string: "pasted ", attributes: [.font: georgia])
        copied.append(NSAttributedString(string: "bold", attributes: [.font: bold]))
        return copied
    }

    /// Paste and drag-and-drop both read through `readSelection(from:type:)`, with the legacy
    /// type names AppKit passes as well as the modern ones.
    @Test(arguments: [
        NSPasteboard.PasteboardType.rtf,
        NSPasteboard.PasteboardType("NeXT Rich Text Format v1.0 pasteboard type"),
    ])
    func readingRichTextKeepsSupportedFormattingAndDropsForeignFonts(
        type: NSPasteboard.PasteboardType
    ) throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([try georgiaText()])
        let textView = makeTextView("start ")
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        let read = textView.readSelection(from: pasteboard, type: type)

        #expect(read)
        #expect(markdown(textView) == "start pasted **bold**")
        let font = textView.attributedString().attribute(.font, at: 8, effectiveRange: nil)
        #expect((font as? NSFont)?.pointSize == RichTextBridge.bodyFontSize)
        #expect(textView.selectedRange() == NSRange(location: 17, length: 0))
    }

    @Test func readingRichTextReplacesTheSelectionAndCanBeUndone() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([NSAttributedString(string: "\t•\tnew")])
        let textView = makeTextView("old text")
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let delegate = UndoDelegate(undoManager: undoManager)
        textView.delegate = delegate
        textView.setSelectedRange(NSRange(location: 0, length: 3))

        undoManager.beginUndoGrouping()
        #expect(textView.readSelection(from: pasteboard, type: .rtf))
        undoManager.endUndoGrouping()
        #expect(textView.string == "• new text")

        undoManager.undo()
        #expect(textView.string == "old text")
    }

    @Test func readingRichTextFromAnEmptyPasteboardReadsNothing() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let textView = makeTextView("keep")

        #expect(!textView.readSelection(from: pasteboard, type: .rtf))
        #expect(textView.string == "keep")
    }

    /// Paste and drag-and-drop read plain text as `NSStringPboardType`, and Paste and Match Style
    /// also tries `NSStringWithLinksPboardType` first.
    @Test(arguments: [
        NSPasteboard.PasteboardType.string,
        NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("NSStringWithLinksPboardType"),
    ])
    func readingPlainTextIgnoresTheTypingStyle(type: NSPasteboard.PasteboardType) {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("plain", forType: .string)
        let textView = makeTextView("bold")
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        textView.toggleBold(nil)
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(RichTextStyle(attributes: textView.typingAttributes).bold)

        #expect(textView.readSelection(from: pasteboard, type: type))

        #expect(markdown(textView) == "**bold**plain")
    }

    @Test func readingPlainTextTurnsListMarkersIntoBulletsAndKeepsOtherMarkdown() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("- one\n* two\n  - three\n**four** -five", forType: .string)
        let textView = makeTextView("")
        textView.toggleBold(nil)

        #expect(textView.readSelection(from: pasteboard, type: .string))

        #expect(textView.string == "• one\n• two\n• three\n**four** -five")
        #expect(markdown(textView) == "- one\n- two\n- three\n\\*\\*four\\*\\* -five")
        let end = (textView.string as NSString).length
        #expect(textView.selectedRange() == NSRange(location: end, length: 0))
    }

    @Test(arguments: [
        ("- a\n* b", "• a\n• b"),
        ("\t-  a\r\n  * b", "• a\r\n• b"),
        ("◦ a", "• a"),
        ("-a\n*b*\n--- c", "-a\n*b*\n--- c"),
        ("a - b * c", "a - b * c"),
        ("", ""),
    ])
    func plainTextTurnsLeadingListMarkersIntoBullets(input: String, expected: String) {
        let text = RichTextBridge.plainText(input)

        #expect(text.string == expected)
        let attributes = text.length > 0 ? text.attributes(at: 0, effectiveRange: nil) : [:]
        #expect(text.length == 0 || RichTextStyle(attributes: attributes) == RichTextStyle())
    }

    @Test func readingPlainTextReplacesTheSelectionAndCanBeUndone() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("- new", forType: .string)
        let textView = makeTextView("old text")
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let delegate = UndoDelegate(undoManager: undoManager)
        textView.delegate = delegate
        textView.setSelectedRange(NSRange(location: 0, length: 3))

        undoManager.beginUndoGrouping()
        #expect(textView.readSelection(from: pasteboard, type: .string))
        undoManager.endUndoGrouping()
        #expect(textView.string == "• new text")

        undoManager.undo()
        #expect(textView.string == "old text")
    }

    @Test func readingPlainTextFromAnEmptyPasteboardReadsNothing() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let textView = makeTextView("keep")

        #expect(!textView.readSelection(from: pasteboard, type: .string))
        #expect(textView.string == "keep")
    }

    private func actions(in menu: NSMenu) -> [String] {
        menu.items.flatMap { item in
            let own = item.action.map(NSStringFromSelector).map { [$0] } ?? []
            return own + (item.submenu.map(actions) ?? [])
        }
    }

    @Test func contextMenuOffersNoFormattingOutsideTheSupportedSubset() throws {
        let textView = makeTextView("hello")
        textView.usesFontPanel = true
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled],
            backing: .buffered, defer: true)
        window.contentView = textView
        let event = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))

        let menu = try #require(textView.menu(for: event))

        let found = actions(in: menu)
        for unsupported in [
            "orderFrontFontPanel:", "underline:", "orderFrontColorPanel:",
            "orderFrontStylesPanel:", "changeLayoutOrientation:",
        ] {
            #expect(!found.contains(unsupported), "\(unsupported) is still in the menu")
        }
        for kept in [
            "cut:", "copy:", "paste:", "pasteAsPlainText:", "toggleContinuousSpellChecking:",
            "toggleAutomaticQuoteSubstitution:", "startSpeaking:", "uppercaseWord:",
        ] {
            #expect(found.contains(kept), "\(kept) is missing from the menu")
        }
    }

    @Test func removingUnsupportedItemsDropsFormattingSubmenusAndStraySeparators() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let font = NSMenuItem(title: "Font", action: nil, keyEquivalent: "")
        font.submenu = NSMenu()
        font.submenu?.addItem(
            withTitle: "Kern", action: #selector(NSTextView.useStandardKerning(_:)),
            keyEquivalent: "")
        menu.addItem(font)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Ligatures", action: #selector(NSTextView.useStandardLigatures(_:)),
            keyEquivalent: "")

        FormattingTextView.removeUnsupportedItems(from: menu)

        #expect(menu.items.map(\.title) == ["Copy"])
    }
}

@MainActor final class UndoDelegate: NSObject, NSTextViewDelegate {
    let undoManager: UndoManager

    init(undoManager: UndoManager) {
        self.undoManager = undoManager
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }
}
