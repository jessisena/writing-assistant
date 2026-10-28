import AppKit
import SwiftUI

/// A formatting command of `FormattingTextView`, shared by the toolbars and the Format menu.
enum FormattingAction: CaseIterable, Identifiable {
    case bold
    case italic
    case strikethrough
    case code
    case bullet

    var id: Self { self }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .code: "Code"
        case .bullet: "Bullet List"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .bullet: "list.bullet"
        }
    }

    var selector: Selector {
        switch self {
        case .bold: #selector(FormattingTextView.toggleBold(_:))
        case .italic: #selector(FormattingTextView.toggleItalic(_:))
        case .strikethrough: #selector(FormattingTextView.toggleStrikethrough(_:))
        case .code: #selector(FormattingTextView.toggleCode(_:))
        case .bullet: #selector(FormattingTextView.toggleBullet(_:))
        }
    }

    var shortcut: KeyboardShortcut? {
        switch self {
        case .bold: KeyboardShortcut("b")
        case .italic: KeyboardShortcut("i")
        case .strikethrough: KeyboardShortcut("x", modifiers: [.command, .shift])
        case .code, .bullet: nil
        }
    }

    /// The title with its shortcut, for tooltips.
    var help: String {
        switch self {
        case .bold: "Bold (⌘B)"
        case .italic: "Italic (⌘I)"
        case .strikethrough: "Strikethrough (⇧⌘X)"
        case .code, .bullet: title
        }
    }
}

/// Formatting buttons and the emoji picker for one editor.
struct FormattingToolbar: View {
    let controller: RichTextController

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FormattingAction.allCases) { action in
                ToolbarIconButton(title: action.title, systemImage: action.systemImage) {
                    controller.perform(action)
                }
                .help(action.help)
            }
            Divider().frame(height: 16)
            ToolbarIconButton(title: "Emoji", systemImage: "face.smiling") {
                controller.showEmojiPicker()
            }
            .help("Emoji & Symbols (⌃⌘Space)")
        }
    }
}

private struct ToolbarIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 18)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }
}

/// The Format menu. It sends to the first responder, so it acts on the focused editor.
struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            ForEach(FormattingAction.allCases) { action in
                Button(action.title) {
                    NSApp.sendAction(action.selector, to: nil, from: nil)
                }
                .keyboardShortcut(action.shortcut)
            }
        }
    }
}
