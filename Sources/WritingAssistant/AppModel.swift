import AppKit
import Observation
import WritingAssistantCore

/// What Copy puts on the clipboard: HTML for apps that keep formatting (Slack, Docs, Mail) and
/// plain text, with link targets written out, for the rest.
struct ClipboardContent: Equatable, Sendable {
    let html: String
    let plain: String
}

/// State and actions for the main window.
@Observable @MainActor final class AppModel {
    static let copiedDuration: Duration = .seconds(2)
    static let channelDefaultsKey = "selectedChannel"

    var input = NSAttributedString()
    var output = NSAttributedString()
    /// The channel to write for. Each change is saved, so the next launch starts with it.
    var channel: Channel {
        didSet { defaults.set(channel.rawValue, forKey: Self.channelDefaultsKey) }
    }
    var isLoading: Bool { requests.isRunning }
    private(set) var result: PolishResult? {
        didSet { showsChanges = false }
    }
    /// Whether the Polished Text card shows the diff instead of the editor. It lives here rather
    /// than in view state because the card is rebuilt after every request. Any change to
    /// `result` turns it off; a refinement only changes `output`, so it keeps it on.
    var showsChanges = false
    private(set) var errorMessage: String?
    private(set) var copied = false
    /// When the running polish or refinement started. Nil when no request is running.
    private(set) var requestStartedAt: Date?
    /// Past requests, newest first. Change it only through the methods in `AppModel+History`.
    var history: [HistoryEntry] = []
    /// The history entry the output on screen belongs to, which `saveOutputToHistory()` updates.
    var currentHistoryID: UUID?

    /// True when there is something to clear and no request is running.
    var canClear: Bool {
        !isLoading
            && (input.length > 0 || output.length > 0 || result != nil || errorMessage != nil)
    }

    @ObservationIgnored let polisher: any Polishing
    @ObservationIgnored private let defaults: UserDefaults
    /// Where `process()` writes each learning summary. Append only from the main actor.
    @ObservationIgnored let learningLog: LearningLog
    @ObservationIgnored let historyStore: HistoryStore
    /// The running polish or refinement, which `cancel()` stops.
    @ObservationIgnored let requests = RequestRunner()
    @ObservationIgnored private let writeToPasteboard: @MainActor (ClipboardContent) -> Void
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private var copyGeneration = 0
    @ObservationIgnored private var startupErrorMessage: String?
    /// False when the history file exists but couldn't be read or moved aside at launch. Saving
    /// is then skipped until the next launch, so the unread file is never overwritten.
    @ObservationIgnored private(set) var savesHistory = true

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - polisher: Service that polishes text.
    ///   - learningLog: The Markdown file learning summaries are appended to.
    ///   - historyStore: Where past requests are kept. It is read here; a damaged file is shown
    ///     in the error banner and the history starts empty. When the file can't be read (or a
    ///     damaged one can't be moved aside), the banner says so and history isn't saved until
    ///     the next launch.
    ///   - writeToPasteboard: Puts the copied text on the clipboard. Defaults to the general
    ///     pasteboard.
    ///   - sleep: Waits before the "Copied" label resets. Defaults to `Task.sleep`.
    ///   - defaults: Where the selected channel is kept between launches. A missing or unknown
    ///     saved value gives Formal document.
    init(
        polisher: any Polishing,
        learningLog: LearningLog = .standard(),
        historyStore: HistoryStore = .standard(),
        writeToPasteboard: @escaping @MainActor (ClipboardContent) -> Void =
            AppModel.writeToGeneralPasteboard,
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        defaults: UserDefaults = .standard
    ) {
        self.polisher = polisher
        self.defaults = defaults
        channel =
            defaults.string(forKey: Self.channelDefaultsKey).flatMap(Channel.init(rawValue:))
            ?? .formal
        self.learningLog = learningLog
        self.historyStore = historyStore
        self.writeToPasteboard = writeToPasteboard
        self.sleep = sleep
        loadHistory()
    }

    private func loadHistory() {
        do {
            history = try historyStore.load()
        } catch HistoryStoreError.corrupted(let backup) {
            showStartupError(HistoryStoreError.corrupted(backup: backup))
        } catch {
            savesHistory = false
            showStartupError(Self.historyNotSavedMessage(error))
        }
    }

    private static func historyNotSavedMessage(_ error: any Error) -> String {
        error.localizedDescription
            + " New history won't be saved until you relaunch the app, so the file isn't replaced."
    }

    /// Starts polishing `input` in a task that `cancel()` can stop. Ignored while a request is
    /// running.
    func startProcessing() {
        guard let request = beginProcessing() else { return }
        requests.start { [self] in await polish(request) }
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
        requests.cancel()
        requestStartedAt = nil
    }

    /// Marks a request as running in `requests` and clears the error banner.
    ///
    /// - Returns: The request's generation for `finishRequest(_:_:)`, or nil when a request is
    ///   already running.
    func beginRequest() -> Int? {
        guard let generation = requests.begin() else { return nil }
        errorMessage = nil
        requestStartedAt = .now
        return generation
    }

    /// Runs the work of the request started as `generation` (see `RequestRunner.finish(_:_:)`)
    /// and shows a failure in the error banner. A cancelled or replaced request shows no error.
    ///
    /// - Returns: The operation's value, or nil when it failed or was cancelled.
    func finishRequest<Value>(
        _ generation: Int, _ operation: () async throws(PolishError) -> Value
    ) async -> Value? {
        let outcome = await requests.finish(generation, operation)
        if !requests.isRunning {
            requestStartedAt = nil
        }
        switch outcome {
        case .success(let value):
            return value
        case .failure(let error):
            errorMessage = error.errorDescription
            return nil
        case nil:
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
        leaveCurrentHistoryEntry()
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
        recordHistory(polished, input: request.text, channel: request.channel)
        appendToLearningLog(polished, channel: request.channel)
    }

    /// Empties the input, the output, the result and the error banner, after saving the edited
    /// output to history. Ignored while a request is running.
    ///
    /// - Parameter undoManager: Gets an undo action named "Clear" that puts back what was on
    ///   screen, including which history entry the output belongs to. The action does nothing
    ///   while a request is running.
    func clear(undoManager: UndoManager?) {
        guard !isLoading else { return }
        let snapshot = ScreenSnapshot(
            input: input, output: output, result: result, errorMessage: errorMessage,
            historyID: currentHistoryID)
        errorMessage = nil
        leaveCurrentHistoryEntry()
        input = NSAttributedString()
        output = NSAttributedString()
        result = nil
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restore(snapshot) }
        }
        undoManager?.setActionName("Clear")
    }

    private struct ScreenSnapshot {
        let input: NSAttributedString
        let output: NSAttributedString
        let result: PolishResult?
        let errorMessage: String?
        let historyID: UUID?
    }

    private func restore(_ snapshot: ScreenSnapshot) {
        guard !isLoading else { return }
        input = snapshot.input
        output = snapshot.output
        result = snapshot.result
        errorMessage = snapshot.errorMessage
        currentHistoryID = snapshot.historyID
    }

    /// Puts a past request back on screen: `input` and the result, with the output editor
    /// showing `result.polishedText`. Clears the error banner.
    func show(_ result: PolishResult, input: NSAttributedString) {
        errorMessage = nil
        self.input = input
        self.result = result
        output = Self.editorText(fromMarkdown: result.polishedText)
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

    /// Adds `error` to the error banner without touching the result, for failures that happen
    /// after a request succeeded, such as a log or history file that couldn't be written.
    func showBanner(_ error: any Error) {
        showBanner(error.localizedDescription)
    }

    /// Adds `message` to the error banner until the next request starts. A message that is
    /// already in the banner isn't repeated.
    func showBanner(_ message: String) {
        guard let current = errorMessage, !current.isEmpty else {
            errorMessage = message
            return
        }
        guard !current.components(separatedBy: "\n").contains(message) else { return }
        errorMessage = current + "\n" + message
    }

    /// Shows a startup failure, such as prompts that couldn't be seeded, in the error banner.
    /// Earlier startup failures stay in the banner.
    func showStartupError(_ error: any Error) {
        showStartupError(error.localizedDescription)
    }

    /// Shows a startup failure message in the error banner. Earlier startup failures stay in it.
    func showStartupError(_ message: String) {
        startupErrorMessage = [startupErrorMessage, message]
            .compactMap { $0 }
            .joined(separator: "\n")
        errorMessage = startupErrorMessage
    }

    /// Copies the edited output as HTML and plain text and shows "Copied" for `copiedDuration`.
    /// The edited output is saved to history first.
    func copyResult() async {
        guard result != nil else { return }
        saveOutputToHistory()
        let text = RichTextBridge.attributedString(from: output)
        writeToPasteboard(
            ClipboardContent(
                html: RichText.html(from: text), plain: RichText.clipboardText(from: text))
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
