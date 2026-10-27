import AppKit
import Observation
import WritingAssistantCore

/// What Copy puts on the clipboard: HTML for apps that keep formatting (Slack, Docs, Mail) and
/// plain text for the rest.
struct ClipboardContent: Equatable, Sendable {
    let html: String
    let plain: String
}

/// State and actions for the main window.
@Observable @MainActor final class AppModel {
    static let copiedDuration: Duration = .seconds(2)

    var input = NSAttributedString()
    var output = NSAttributedString()
    var channel: Channel = .formal
    private(set) var isLoading = false
    private(set) var result: PolishResult?
    private(set) var errorMessage: String?
    private(set) var copied = false

    @ObservationIgnored private let polisher: any Polishing
    @ObservationIgnored private let writeToPasteboard: @MainActor (ClipboardContent) -> Void
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private var copyGeneration = 0
    @ObservationIgnored private var startupErrorMessage: String?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - polisher: Service that polishes text.
    ///   - writeToPasteboard: Puts the copied text on the clipboard. Defaults to the general
    ///     pasteboard.
    ///   - sleep: Waits before the "Copied" label resets. Defaults to `Task.sleep`.
    init(
        polisher: any Polishing,
        writeToPasteboard: @escaping @MainActor (ClipboardContent) -> Void =
            AppModel.writeToGeneralPasteboard,
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.polisher = polisher
        self.writeToPasteboard = writeToPasteboard
        self.sleep = sleep
    }

    /// Polishes `input`, sent as Markdown, with the selected channel. Ignored while a request
    /// is running.
    func process() async {
        guard !isLoading else { return }
        let text = RichText.markdown(from: RichTextBridge.attributedString(from: input))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = PolishError.emptyInput.errorDescription
            return
        }
        errorMessage = nil
        result = nil
        output = NSAttributedString()
        isLoading = true
        defer { isLoading = false }
        do {
            let polished = try await polisher.polish(text: text, channel: channel)
            result = polished
            output = Self.editorText(fromMarkdown: polished.polishedText)
        } catch {
            result = nil
            errorMessage = error.errorDescription
        }
    }

    /// Shows a banner when the polisher can't run (for example, the claude CLI is missing).
    /// A startup error already in the banner is kept, followed by the readiness message.
    func checkReadiness() async {
        do {
            try await polisher.checkReady()
        } catch {
            errorMessage = [startupErrorMessage, error.errorDescription]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
    }

    /// Shows a startup failure, such as prompts that couldn't be seeded, in the error banner.
    func showStartupError(_ error: any Error) {
        startupErrorMessage = error.localizedDescription
        errorMessage = startupErrorMessage
    }

    /// Copies the edited output as HTML and plain text and shows "Copied" for `copiedDuration`.
    func copyResult() async {
        guard result != nil else { return }
        let text = RichTextBridge.attributedString(from: output)
        writeToPasteboard(
            ClipboardContent(html: RichText.html(from: text), plain: RichText.plainText(from: text))
        )
        copied = true
        copyGeneration += 1
        let generation = copyGeneration
        await sleep(Self.copiedDuration)
        if generation == copyGeneration {
            copied = false
        }
    }

    /// Converts Markdown from Claude into text for the output editor.
    static func editorText(fromMarkdown markdown: String) -> NSAttributedString {
        RichTextBridge.nsAttributedString(from: RichText.attributedString(fromMarkdown: markdown))
    }

    static func writeToGeneralPasteboard(_ content: ClipboardContent) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content.html, forType: .html)
        pasteboard.setString(content.plain, forType: .string)
    }
}
