import AppKit
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct ListContinuationTests {
    private func makeTextView(_ text: String, caret: Int) -> FormattingTextView {
        let textView = FormattingTextView.make()
        textView.setContents(
            NSAttributedString(string: text, attributes: RichTextBridge.baseAttributes))
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return textView
    }

    private func markdown(_ textView: NSTextView) -> String {
        RichText.markdown(from: RichTextBridge.attributedString(from: textView.attributedString()))
    }

    @Test(arguments: [
        ("• one", NSRange(location: 5, length: 0), FormattingTextView.ListReturn.continueList),
        ("• onetwo", NSRange(location: 5, length: 0), .continueList),
        ("• one two", NSRange(location: 2, length: 3), .continueList),
        ("• one\n• two", NSRange(location: 5, length: 0), .continueList),
        ("• ", NSRange(location: 2, length: 0), .endList(NSRange(location: 0, length: 2))),
        ("a\n• ", NSRange(location: 4, length: 0), .endList(NSRange(location: 2, length: 2))),
        ("• a\n• \nb", NSRange(location: 6, length: 0), .endList(NSRange(location: 4, length: 2))),
    ])
    func returnOnABulletLine(
        text: String, selection: NSRange, expected: FormattingTextView.ListReturn
    ) {
        #expect(FormattingTextView.listReturn(in: text, selection: selection) == expected)
    }

    @Test(arguments: [
        ("plain", NSRange(location: 5, length: 0)),
        ("• one", NSRange(location: 0, length: 0)),
        ("• one", NSRange(location: 1, length: 0)),
        ("• one\nplain", NSRange(location: 11, length: 0)),
        ("", NSRange(location: 0, length: 0)),
        ("• one\n", NSRange(location: 6, length: 0)),
    ])
    func returnOutsideABulletLineIsLeftToTheTextView(text: String, selection: NSRange) {
        #expect(FormattingTextView.listReturn(in: text, selection: selection) == nil)
    }

    @Test func returnContinuesTheListThenEndsItOnTheEmptyBullet() {
        let textView = makeTextView("• one", caret: 5)

        textView.insertNewline(nil)
        #expect(textView.string == "• one\n• ")
        #expect(textView.selectedRange() == NSRange(location: 8, length: 0))

        textView.insertNewline(nil)
        #expect(textView.string == "• one\n")
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test func returnInsideABulletLineMovesTheRestToANewBullet() {
        let textView = makeTextView("• onetwo", caret: 5)

        textView.insertNewline(nil)

        #expect(textView.string == "• one\n• two")
        #expect(textView.selectedRange() == NSRange(location: 8, length: 0))
    }

    @Test func returnOnAPlainLineInsertsANewline() {
        let textView = makeTextView("plain", caret: 5)

        textView.insertNewline(nil)

        #expect(textView.string == "plain\n")
    }

    @Test func continuingTheListKeepsTheTypingStyle() {
        let textView = makeTextView("• one", caret: 5)
        textView.toggleBold(nil)

        textView.insertNewline(nil)
        textView.insertText("two", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(markdown(textView) == "- one\n- **two**")
    }

    @Test func endingTheListKeepsTheTypingStyle() {
        let textView = makeTextView("• ", caret: 2)
        textView.toggleItalic(nil)

        textView.insertNewline(nil)

        #expect(RichTextStyle(attributes: textView.typingAttributes).italic)
    }

    @Test(arguments: [("• one", 5), ("• one\n• ", 8)])
    func returnOnABulletLineIsUndoneInOneStep(text: String, caret: Int) {
        let textView = makeTextView(text, caret: caret)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let delegate = UndoDelegate(undoManager: undoManager)
        textView.delegate = delegate

        undoManager.beginUndoGrouping()
        textView.insertNewline(nil)
        undoManager.endUndoGrouping()
        #expect(textView.string != text)

        undoManager.undo()
        #expect(textView.string == text)
    }
}
