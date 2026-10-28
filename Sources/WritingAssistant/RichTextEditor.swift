import AppKit
import Observation
import SwiftUI
import WritingAssistantCore

/// Converts between the editors' `NSAttributedString` and the `AttributedString` that
/// `RichText` reads and writes.
///
/// Only the supported subset survives: bold, italic, strikethrough, code (a monospaced font),
/// links and headings. Fonts, sizes and colors from elsewhere are replaced with the editor's own,
/// so pasted text looks like typed text and stays readable in dark mode.
enum RichTextBridge {
    static let bodyFontSize: CGFloat = 15
    static let lineHeightMultiple: CGFloat = 1.35
    static let bulletPrefix = "• "
    static let headingLevelKey = NSAttributedString.Key("WritingAssistant.headingLevel")

    /// Attributes for unformatted text.
    static var baseAttributes: [NSAttributedString.Key: Any] { RichTextStyle().applied(to: [:]) }

    /// Bullet markers that rich text from other apps puts at the start of list lines. A literal,
    /// so the compiler checks the pattern; computed because `Regex` isn't `Sendable`.
    private static var foreignListMarker: Regex<Substring> {
        #/^[\t ]*(?:[•◦▪▫●○■□‣⁃∙]|-(?=\t))[\t ]+/#.anchorsMatchLineEndings()
    }

    /// List markers that start a line of plain text: the foreign bullets, and Markdown's `-` and
    /// `*` followed by a space.
    private static var plainListMarker: Regex<Substring> {
        #/^[\t ]*[•◦▪▫●○■□‣⁃∙\-*][\t ]+/#.anchorsMatchLineEndings()
    }

    /// Builds unformatted editor text from pasted plain text, with list markers turned into
    /// `"• "` bullets. Other Markdown, such as `**`, stays literal.
    ///
    /// - Parameter string: Plain text from the pasteboard.
    /// - Returns: Text in the base style, whatever the typing style is.
    static func plainText(_ string: String) -> NSAttributedString {
        let bulleted = string.replacing(plainListMarker, with: bulletPrefix)
        return NSAttributedString(string: bulleted, attributes: baseAttributes)
    }

    /// Reads the supported formatting from editor text. Attachments are dropped.
    ///
    /// - Parameter text: Text from an editor or the pasteboard.
    /// - Returns: The text with `inlinePresentationIntent`, `link` and `headingLevel` set.
    static func attributedString(from text: NSAttributedString) -> AttributedString {
        var result = AttributedString()
        let fullRange = NSRange(location: 0, length: text.length)
        text.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard attributes[.attachment] == nil else { return }
            let style = RichTextStyle(attributes: attributes)
            var run = AttributedString(text.attributedSubstring(from: range).string)
            run.inlinePresentationIntent = style.intent
            run.link = link(from: attributes[.link])
            run.headingLevel = style.headingLevel
            result += run
        }
        return result
    }

    /// Builds editor text, with the editor's fonts and colors, from rich text.
    ///
    /// - Parameter text: Text using the attributes `RichText` supports.
    /// - Returns: Text ready for a `FormattingTextView`.
    static func nsAttributedString(from text: AttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs {
            let style = RichTextStyle(
                intent: run.inlinePresentationIntent, headingLevel: run.headingLevel)
            var attributes = style.applied(to: [:])
            attributes[.link] = run.link
            let string = String(text[run.range].characters)
            result.append(NSAttributedString(string: string, attributes: attributes))
        }
        return result
    }

    /// Keeps only the supported formatting of pasted text and turns foreign list markers into
    /// `"• "` bullets.
    ///
    /// - Parameter text: Rich text from another app, such as Google Docs or Slack.
    /// - Returns: Text with the editor's fonts and colors.
    static func normalized(_ text: NSAttributedString) -> NSAttributedString {
        nsAttributedString(from: attributedString(from: replacingListMarkers(in: text)))
    }

    private static func replacingListMarkers(in text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let string = text.string
        for match in string.matches(of: foreignListMarker).reversed() {
            result.replaceCharacters(in: NSRange(match.range, in: string), with: bulletPrefix)
        }
        return result
    }

    private static func link(from value: Any?) -> URL? {
        if let url = value as? URL {
            return url
        }
        return (value as? String).flatMap(URL.init(string:))
    }
}

/// The supported formatting of one run of editor text, and the attributes that show it.
struct RichTextStyle: Equatable {
    var bold = false
    var italic = false
    var strikethrough = false
    var code = false
    var headingLevel: Int?

    init() {}

    /// Reads the style from `NSAttributedString` attributes. Headings are always bold, so a
    /// heading's bold font doesn't count as bold text.
    init(attributes: [NSAttributedString.Key: Any]) {
        let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        headingLevel = attributes[RichTextBridge.headingLevelKey] as? Int
        bold = traits.contains(.bold) && headingLevel == nil
        italic = traits.contains(.italic)
        code = traits.contains(.monoSpace)
        strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
    }

    init(intent: InlinePresentationIntent?, headingLevel: Int?) {
        let intent = intent ?? []
        bold = intent.contains(.stronglyEmphasized)
        italic = intent.contains(.emphasized)
        strikethrough = intent.contains(.strikethrough)
        code = intent.contains(.code)
        self.headingLevel = headingLevel
    }

    var intent: InlinePresentationIntent? {
        var intent: InlinePresentationIntent = []
        if bold { intent.insert(.stronglyEmphasized) }
        if italic { intent.insert(.emphasized) }
        if strikethrough { intent.insert(.strikethrough) }
        if code { intent.insert(.code) }
        return intent.isEmpty ? nil : intent
    }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = RichTextBridge.lineHeightMultiple
        return style
    }

    /// Returns `attributes` with the font, color, line spacing, strikethrough and heading level
    /// replaced by this style's. Other attributes, such as links, are kept.
    func applied(
        to attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var result = attributes
        result[.font] = font
        result[.foregroundColor] = NSColor.textColor
        result[.paragraphStyle] = Self.paragraphStyle
        result[.strikethroughStyle] = strikethrough ? NSUnderlineStyle.single.rawValue : nil
        result[RichTextBridge.headingLevelKey] = headingLevel
        return result
    }

    var font: NSFont {
        let size = headingLevel.map(Self.headingSize) ?? RichTextBridge.bodyFontSize
        let base =
            code
            ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont.systemFont(ofSize: size)
        var traits = base.fontDescriptor.symbolicTraits
        if bold || headingLevel != nil { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 20
        case 2: 17
        default: 15
        }
    }
}

/// Rich text view for the editors: no images, spell check, its own formatting actions, and
/// pasting that keeps only the supported formatting.
final class FormattingTextView: NSTextView {
    /// Called with true when the view becomes first responder and false when it resigns.
    var onFocusChange: (@MainActor (Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }

    /// Creates a text view configured for the editors.
    static func make() -> FormattingTextView {
        let textView = FormattingTextView(frame: .zero)
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.usesFontPanel = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.typingAttributes = RichTextBridge.baseAttributes
        return textView
    }

    @objc func toggleBold(_ sender: Any?) { toggle(\.bold) }
    @objc func toggleItalic(_ sender: Any?) { toggle(\.italic) }
    @objc func toggleStrikethrough(_ sender: Any?) { toggle(\.strikethrough) }
    @objc func toggleCode(_ sender: Any?) { toggle(\.code) }

    /// Adds a `"• "` bullet to every selected paragraph, or removes them when all have one.
    @objc func toggleBullet(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let selection = selectedRange()
        let paragraphs = (string as NSString).paragraphRange(for: selection)
        let updated = Self.togglingBullets(in: storage.attributedSubstring(from: paragraphs))
        guard shouldChangeText(in: paragraphs, replacementString: updated.string) else { return }
        storage.replaceCharacters(in: paragraphs, with: updated)
        didChangeText()
        if selection.length == 0 {
            let delta = updated.length - paragraphs.length
            let caret = max(paragraphs.location, selection.location + delta)
            setSelectedRange(NSRange(location: caret, length: 0))
        } else {
            setSelectedRange(NSRange(location: paragraphs.location, length: updated.length))
        }
    }

    /// What Return does on a bulleted line.
    enum ListReturn: Equatable {
        /// Starts a new bulleted line, replacing the selection.
        case continueList
        /// Removes the bullet at the range from its otherwise empty line, which ends the list.
        case endList(NSRange)
    }

    /// Return on a bulleted line continues the list, and on an empty bulleted line ends it, as
    /// in Notes. Other lines get a plain newline.
    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        switch Self.listReturn(in: string, selection: selection) {
        case nil:
            super.insertNewline(sender)
        case .continueList:
            let newline = NSMutableAttributedString(string: "\n", attributes: typingAttributes)
            newline.append(
                NSAttributedString(
                    string: RichTextBridge.bulletPrefix, attributes: RichTextBridge.baseAttributes))
            replaceKeepingTypingStyle(selection, with: newline)
        case .endList(let bullet):
            replaceKeepingTypingStyle(bullet, with: NSAttributedString())
        }
    }

    /// Decides what Return does when `selection` is in `text`.
    ///
    /// - Returns: Nil unless the selection starts after the `"• "` of a bulleted line.
    static func listReturn(in text: String, selection: NSRange) -> ListReturn? {
        let string = text as NSString
        let prefix = RichTextBridge.bulletPrefix
        let prefixLength = (prefix as NSString).length
        let paragraph = string.paragraphRange(for: NSRange(location: selection.location, length: 0))
        let line = string.substring(with: paragraph)
        guard line.hasPrefix(prefix), selection.location >= paragraph.location + prefixLength
        else { return nil }
        if selection.length == 0, line.trimmingCharacters(in: .newlines) == prefix {
            return .endList(NSRange(location: paragraph.location, length: prefixLength))
        }
        return .continueList
    }

    /// Replaces `range` with `text` as one undoable step and leaves the caret after it, with the
    /// typing style it had before.
    private func replaceKeepingTypingStyle(_ range: NSRange, with text: NSAttributedString) {
        let attributes = typingAttributes
        breakUndoCoalescing()
        replace(range, with: text)
        typingAttributes = attributes
    }

    /// Replaces `range` with `text` as one undoable step and puts the caret after it.
    private func replace(_ range: NSRange, with text: NSAttributedString) {
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: text.string)
        else { return }
        storage.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + text.length, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    /// Pasteboard types that carry another app's formatting, under both the modern names and the
    /// legacy ones AppKit passes to `readSelection(from:type:)`.
    private static let richTextTypes: Set<NSPasteboard.PasteboardType> = [
        .rtf, .rtfd, .html, NSPasteboard.PasteboardType("com.apple.flat-rtfd"),
        NSPasteboard.PasteboardType("NeXT Rich Text Format v1.0 pasteboard type"),
        NSPasteboard.PasteboardType("NeXT RTFD pasteboard type"),
        NSPasteboard.PasteboardType("Apple HTML pasteboard type"),
    ]

    /// Pasteboard types of plain text: the modern name and the legacy ones AppKit passes for
    /// paste, drag-and-drop and Paste and Match Style.
    private static let plainTextTypes: Set<NSPasteboard.PasteboardType> = [
        .string, NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("NSStringWithLinksPboardType"),
    ]

    /// Reads pasted or dropped text into the selection. Paste, Paste and Match Style and
    /// drag-and-drop all come through here. Rich text keeps only the supported formatting.
    /// Plain text gets the base style rather than the typing style, with its list markers
    /// turned into bullets. Other types are left to `NSTextView`.
    ///
    /// - Returns: False when the pasteboard holds no text of `type`.
    override func readSelection(
        from pboard: NSPasteboard, type: NSPasteboard.PasteboardType
    ) -> Bool {
        if Self.plainTextTypes.contains(type) {
            guard let pasted = pboard.string(forType: .string) else { return false }
            replace(selectedRange(), with: RichTextBridge.plainText(pasted))
            return true
        }
        guard Self.richTextTypes.contains(type) else {
            return super.readSelection(from: pboard, type: type)
        }
        let objects = pboard.readObjects(forClasses: [NSAttributedString.self])
        guard let pasted = objects?.first as? NSAttributedString else { return false }
        replace(selectedRange(), with: RichTextBridge.normalized(pasted))
        return true
    }

    /// Actions of context menu items that apply formatting the editors don't keep, such as
    /// underline, colors, kerning, ligatures and vertical layout.
    private static let unsupportedMenuActions: Set<String> = [
        "orderFrontFontPanel:", "addFontTrait:", "underline:", "outline:", "highlight:",
        "orderFrontStylesPanel:", "orderFrontColorPanel:", "copyFont:", "pasteFont:",
        "useStandardKerning:", "turnOffKerning:", "tightenKerning:", "loosenKerning:",
        "useStandardLigatures:", "turnOffLigatures:", "useAllLigatures:",
        "changeLayoutOrientation:",
    ]

    /// The standard context menu without its Font, Styles and Layout Orientation items. Spelling,
    /// Substitutions, Transformations, Speech and the edit commands stay.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event)?.copy() as? NSMenu else { return nil }
        Self.removeUnsupportedItems(from: menu)
        return menu
    }

    /// Removes every item of `menu` whose action, or any action in whose submenu, is in
    /// `unsupportedMenuActions`, then the separators left at the ends or next to each other.
    static func removeUnsupportedItems(from menu: NSMenu) {
        for item in menu.items where hasUnsupportedAction(item) {
            menu.removeItem(item)
        }
        var previousIsSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousIsSeparator {
                menu.removeItem(item)
            }
            previousIsSeparator = item.isSeparatorItem
        }
        if let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }

    private static func hasUnsupportedAction(_ item: NSMenuItem) -> Bool {
        if let action = item.action, unsupportedMenuActions.contains(NSStringFromSelector(action)) {
            return true
        }
        return item.submenu?.items.contains(where: hasUnsupportedAction) ?? false
    }

    /// Shows `text` unless it is already shown. Undo history is dropped, since it refers to the
    /// replaced text.
    func setContents(_ text: NSAttributedString) {
        guard !attributedString().isEqual(to: text) else { return }
        textStorage?.setAttributedString(text)
        undoManager?.removeAllActions()
        if text.length == 0 {
            typingAttributes = RichTextBridge.baseAttributes
        }
    }

    /// Turns `flag` on for the whole selection, or off when the whole selection already has
    /// it. With nothing selected, it changes the style of the next typed text.
    private func toggle(_ flag: WritableKeyPath<RichTextStyle, Bool>) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else {
            var style = RichTextStyle(attributes: typingAttributes)
            style[keyPath: flag].toggle()
            typingAttributes = style.applied(to: typingAttributes)
            return
        }
        var allHaveFlag = true
        storage.enumerateAttributes(in: range) { attributes, _, stop in
            if !RichTextStyle(attributes: attributes)[keyPath: flag] {
                allHaveFlag = false
                stop.pointee = true
            }
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attributes, subrange, _ in
            var style = RichTextStyle(attributes: attributes)
            style[keyPath: flag] = !allHaveFlag
            storage.setAttributes(style.applied(to: attributes), range: subrange)
        }
        storage.endEditing()
        didChangeText()
    }

    /// Adds a bullet to each non-empty paragraph of `text`, or removes the bullets when every
    /// non-empty paragraph already has one. Empty text gets a single bullet.
    static func togglingBullets(in text: NSAttributedString) -> NSAttributedString {
        let string = text.string as NSString
        let prefix = RichTextBridge.bulletPrefix
        var starts: [Int] = []
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, range, _, _ in
            if range.length > 0 { starts.append(range.location) }
        }
        if starts.isEmpty { starts = [0] }
        let hasBullet = { (start: Int) in
            string.substring(from: start).hasPrefix(prefix)
        }
        let removing = starts.allSatisfy(hasBullet)
        let result = NSMutableAttributedString(attributedString: text)
        let bullet = NSAttributedString(string: prefix, attributes: RichTextBridge.baseAttributes)
        for start in starts.reversed() {
            if removing {
                result.deleteCharacters(in: NSRange(location: start, length: bullet.length))
            } else if !hasBullet(start) {
                result.insert(bullet, at: start)
            }
        }
        return result
    }
}

/// Lets a toolbar act on its own editor, whether or not that editor has focus.
@Observable @MainActor final class RichTextController {
    @ObservationIgnored weak var textView: FormattingTextView?
    /// Whether the editor is the window's first responder.
    var isFocused = false

    /// Focuses the editor and applies `action` to its selection.
    func perform(_ action: FormattingAction) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        NSApp.sendAction(action.selector, to: textView, from: nil)
    }

    /// Focuses the editor and opens the system emoji picker.
    func showEmojiPicker() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        NSApp.orderFrontCharacterPalette(nil)
    }
}

/// A rich text editor with a placeholder, bordered unless `isBordered` is false. It grows with
/// its text between `minHeight` and `maxHeight`, then scrolls.
struct RichTextEditor: View {
    @Binding var text: NSAttributedString
    let controller: RichTextController
    let accessibilityLabel: String
    var placeholder: String?
    var minHeight: CGFloat = 160
    var maxHeight: CGFloat = 400
    /// When false the editor draws no background, clipping or border, so its parent can draw
    /// them.
    var isBordered = true

    var body: some View {
        if isBordered {
            editor
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        } else {
            editor
        }
    }

    private var editor: some View {
        FormattingTextViewRepresentable(
            text: $text,
            controller: controller,
            accessibilityLabel: accessibilityLabel,
            heightRange: minHeight...maxHeight
        )
        .overlay(alignment: .topLeading) {
            if let placeholder, text.length == 0 {
                Text(placeholder)
                    .font(.system(size: RichTextBridge.bodyFontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct FormattingTextViewRepresentable: NSViewRepresentable {
    @Binding var text: NSAttributedString
    let controller: RichTextController
    let accessibilityLabel: String
    let heightRange: ClosedRange<CGFloat>

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FormattingTextView.make()
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setContents(text)
        textView.onFocusChange = { [weak controller] in controller?.isFocused = $0 }
        controller.textView = textView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        guard let textView = scrollView.documentView as? FormattingTextView else { return }
        controller.textView = textView
        // Compare against the last value exchanged with the binding, not the text storage,
        // which adjusts fonts (emoji, CJK) on its own and would never compare equal.
        guard text !== coordinator.lastSynced, !text.isEqual(to: coordinator.lastSynced) else {
            return
        }
        coordinator.lastSynced = text
        textView.setContents(text)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite,
            let textView = scrollView.documentView as? NSTextView
        else { return nil }
        let inset = textView.textContainerInset
        let padding = textView.textContainer?.lineFragmentPadding ?? 0
        let textWidth = max(width - 2 * (inset.width + padding), 1)
        let bounds = textView.attributedString().boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = ceil(bounds.height) + 2 * inset.height
        return CGSize(
            width: width,
            height: min(max(height, heightRange.lowerBound), heightRange.upperBound)
        )
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<NSAttributedString>
        var lastSynced: NSAttributedString
        private let undoManager = UndoManager()

        init(text: Binding<NSAttributedString>) {
            self.text = text
            lastSynced = text.wrappedValue
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let value = NSAttributedString(attributedString: textView.attributedString())
            lastSynced = value
            text.wrappedValue = value
        }

        /// Gives each editor its own undo stack, so undo in one editor never changes the other.
        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }
    }
}
