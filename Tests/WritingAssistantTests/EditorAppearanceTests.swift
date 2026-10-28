import AppKit
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct EditorAppearanceTests {
    @Test func editorTextIsFifteenPointWithRoomyLineSpacing() throws {
        let text = RichTextBridge.nsAttributedString(
            from: RichText.attributedString(fromMarkdown: "Hello **world**"))

        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let style = try #require(
            text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(font.pointSize == 15)
        #expect(style.lineHeightMultiple == 1.35)
    }

    @Test func pastedTextGetsTheEditorLineSpacing() throws {
        let normalized = RichTextBridge.normalized(NSAttributedString(string: "Pasted"))

        let style = try #require(
            normalized.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.lineHeightMultiple == 1.35)
    }

    @Test func controllerTracksWhetherTheEditorHasFocus() {
        let controller = RichTextController()
        let textView = FormattingTextView.make()
        textView.onFocusChange = { [weak controller] in controller?.isFocused = $0 }
        #expect(!controller.isFocused)

        _ = textView.becomeFirstResponder()
        #expect(controller.isFocused)

        _ = textView.resignFirstResponder()
        #expect(!controller.isFocused)
    }
}
