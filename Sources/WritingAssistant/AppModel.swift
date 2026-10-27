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

    /// True when there is something to clear and no request is running.
    var canClear: Bool {
        !isLoading
            && (input.length > 0 || output.length > 0 || result != nil || errorMessage != nil)
    }

    @ObservationIgnored let polisher: any Polishing
    /// The request started by `startProcessing()`, which `cancel()` stops.
    @ObservationIgnored var requestTask: Task<Void, Never>?
    @ObservationIgnored private var requestGeneration = 0
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

    /// Starts polishing `input` in a task that `cancel()` can stop. Ignored while a request is
    /// running.
    func startProcessing() {
        guard let request = beginProcessing() else { return }
        requestTask = Task { await polish(request) }
    }

    /// Polishes `input`, sent as Markdown, with the selected channel. Ignored while a request
    /// is running.
    func process() async {
        guard let request = beginProcessing() else { return }
        await polish(request)
    }

    /// Stops the running request and returns to the empty state, with no error banner. A
    /// late answer from the stopped request is ignored.
    func cancel() {
        guard isLoading else { return }
        requestTask?.cancel()
        requestGeneration += 1
        isLoading = false
    }

    /// Marks a request as running and clears the error banner.
    ///
    /// - Returns: The request's generation for `finishRequest(_:_:)`, or nil when a request is
    ///   already running.
    func beginRequest() -> Int? {
        guard !isLoading else { return nil }
        errorMessage = nil
        isLoading = true
        requestGeneration += 1
        return requestGeneration
    }

    /// Runs the work of the request started as `generation` and ends its loading state.
    ///
    /// A request that was cancelled, or replaced by a newer one, changes nothing and shows no
    /// error. A failure is shown in the error banner.
    ///
    /// - Returns: The operation's value, or nil when it failed or was cancelled.
    func finishRequest<Value>(
        _ generation: Int, _ operation: () async throws(PolishError) -> Value
    ) async -> Value? {
        let outcome: Result<Value, PolishError>
        do {
            outcome = .success(try await operation())
        } catch {
            outcome = .failure(error)
        }
        guard generation == requestGeneration else { return nil }
        isLoading = false
        guard !Task.isCancelled else { return nil }
        switch outcome {
        case .success(let value):
            return value
        case .failure(let error):
            errorMessage = error.errorDescription
            return nil
        }
    }

    private struct PolishRequest {
        let text: String
        let channel: Channel
        let generation: Int
    }

    private func beginProcessing() -> PolishRequest? {
        guard !isLoading else { return nil }
        let text = RichText.markdown(from: RichTextBridge.attributedString(from: input))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = PolishError.emptyInput.errorDescription
            return nil
        }
        guard let generation = beginRequest() else { return nil }
        result = nil
        output = NSAttributedString()
        return PolishRequest(text: text, channel: channel, generation: generation)
    }

    private func polish(_ request: PolishRequest) async {
        let polisher = polisher
        let polished = await finishRequest(request.generation) { () async throws(PolishError) in
            try await polisher.polish(text: request.text, channel: request.channel)
        }
        guard let polished else { return }
        result = polished
        output = Self.editorText(fromMarkdown: polished.polishedText)
    }

    /// Empties the input, the output, the result and the error banner. Ignored while a request
    /// is running.
    func clear() {
        guard !isLoading else { return }
        input = NSAttributedString()
        output = NSAttributedString()
        result = nil
        errorMessage = nil
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
