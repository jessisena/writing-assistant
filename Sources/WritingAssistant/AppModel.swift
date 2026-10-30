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
    static let learningSummaryDefaultsKey = "learningSummaryEnabled"
    /// The shortest time between two streamed text updates on screen (about 30 per second).
    /// Each update parses the Markdown so far and replaces the editor's text, so following
    /// every streamed piece (often 50–100 a second) would redo that work several times per frame
    /// for no visible gain.
    static let previewInterval: Duration = .milliseconds(33)
    /// The time between two streamed updates is also at least this many times what the last
    /// update took, so updates use at most a fifth of the main actor however long the text
    /// grows. Converting the Markdown takes about 3.5 ms for 2,000 characters and 44 ms for
    /// 20,000 (debug build), growing linearly.
    static let previewCostFactor = 5

    var input = NSAttributedString()
    var output = NSAttributedString()
    /// The channel to write for. Each change is saved, so the next launch starts with it.
    var channel: Channel {
        didSet { defaults.set(channel.rawValue, forKey: Self.channelDefaultsKey) }
    }
    /// Whether a polish asks for the English learning summary. Turning it off saves time and
    /// tokens. Each change is saved, so the next launch keeps it.
    var includesLearningSummary: Bool {
        didSet { defaults.set(includesLearningSummary, forKey: Self.learningSummaryDefaultsKey) }
    }
    var isLoading: Bool { requests.isRunning }
    private(set) var result: PolishResult? {
        didSet { showsChanges = false }
    }
    /// Whether the Polished Text card shows the diff instead of the editor. It lives here rather
    /// than in view state because the card is rebuilt after every request. Any change to
    /// `result` turns it off; a refinement only changes `output`, so it keeps it on.
    var showsChanges = false
    /// True while a polish shows its polished text but its learning summary is still coming.
    private(set) var isAwaitingSummary = false
    /// True while a polish shows its polished text as it streams in, before it is complete. The
    /// output is read-only and Copy is off until then, so nothing is edited or copied that the
    /// next update would replace.
    private(set) var isStreamingText = false
    /// What the running polish is doing, for its status line. Nil when no polish is running.
    private(set) var polishStage: PolishStage?
    private(set) var errorMessage: String?
    private(set) var copied = false
    /// Counts successful copies, so views can react to every copy, even two within `copiedDuration`.
    private(set) var copyGeneration = 0
    /// When the running polish or refinement started. Nil when no request is running.
    private(set) var requestStartedAt: Date?
    /// The refinement that is running, or nil when none is (a polish request leaves it nil).
    private(set) var runningRefinement: Refinement?
    /// Past requests, newest first. Change it only through the methods in `AppModel+History`.
    var history: [HistoryEntry] = []
    /// The history entry the output on screen belongs to, which `saveOutputToHistory()` updates.
    var currentHistoryID: UUID?
    /// Tokens used this calendar month, read from `usageStore` at launch and after each request.
    private(set) var monthlyUsage = MonthlyUsage.zero

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
    /// Where the polisher records the tokens each request uses; the model only reads it.
    @ObservationIgnored let usageStore: UsageStore
    /// The running polish or refinement, which `cancel()` stops.
    @ObservationIgnored let requests = RequestRunner()
    @ObservationIgnored private let writeToPasteboard: @MainActor (ClipboardContent) -> Void
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private var startupErrorMessage: String?
    /// False when the history file exists but couldn't be read or moved aside at launch. Saving
    /// is then skipped until the next launch, so the unread file is never overwritten.
    @ObservationIgnored private(set) var savesHistory = true
    /// The preview on screen for the running polish. It is kept until the request ends, so a
    /// cancel or failure can still save the polished text to history.
    @ObservationIgnored private var shownPreview: ShownPreview?
    /// When the next streamed preview may reach the screen (see `previewInterval`).
    @ObservationIgnored private var nextPreviewAt: ContinuousClock.Instant?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - polisher: Service that polishes text.
    ///   - learningLog: The Markdown file learning summaries are appended to.
    ///   - historyStore: Where past requests are kept. It is read here; a damaged file is shown
    ///     in the error banner and the history starts empty. When the file can't be read (or a
    ///     damaged one can't be moved aside), the banner says so and history isn't saved until
    ///     the next launch.
    ///   - usageStore: The monthly token totals, read here and after every request. A file that
    ///     can't be read is shown in the error banner and the count shows zero.
    ///   - writeToPasteboard: Puts the copied text on the clipboard. Defaults to the general
    ///     pasteboard.
    ///   - sleep: Waits before the "Copied" label resets. Defaults to `Task.sleep`.
    ///   - defaults: Where the selected channel and the learning summary setting are kept
    ///     between launches. A missing or unknown saved channel gives Formal document; a missing
    ///     summary setting turns the summary on.
    init(
        polisher: any Polishing,
        learningLog: LearningLog = .standard(),
        historyStore: HistoryStore = .standard(),
        usageStore: UsageStore = .standard(),
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
        includesLearningSummary =
            defaults.object(forKey: Self.learningSummaryDefaultsKey) as? Bool ?? true
        self.learningLog = learningLog
        self.historyStore = historyStore
        self.usageStore = usageStore
        self.writeToPasteboard = writeToPasteboard
        self.sleep = sleep
        loadHistory()
        do {
            monthlyUsage = try usageStore.currentMonth()
        } catch {
            showStartupError(error)
        }
    }

    /// Reads this month's token totals again. A failure goes to the error banner and leaves the
    /// count at zero; a damaged file was moved aside, so the next read starts from zero.
    func refreshMonthlyUsage() {
        do {
            monthlyUsage = try usageStore.currentMonth()
        } catch {
            monthlyUsage = .zero
            showBanner(error)
        }
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

    /// Puts `text` in the input, ready for the user to polish, as the Services entry does. The
    /// output on screen is saved to its history entry first; the result, the output and the error
    /// banner are cleared. Nothing is sent to Claude. Ignored while a request is running.
    func loadInput(_ text: NSAttributedString) {
        guard !isLoading else { return }
        errorMessage = nil
        leaveCurrentHistoryEntry()
        input = text
        output = NSAttributedString()
        result = nil
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

    /// Stops the running request, with no error banner. A late answer from the stopped request
    /// is ignored. A polish that already showed its complete polished text keeps it on screen and
    /// saves it to history without a learning summary; otherwise, including text that was still
    /// streaming in, the screen returns to the empty state.
    func cancel() {
        requests.cancel()
        requestStartedAt = nil
        runningRefinement = nil
        polishStage = nil
        if let shown = endPreview() {
            endWithoutResult(shown)
        }
    }

    /// Marks a request as running in `requests` and clears the error banner.
    ///
    /// - Parameter refinement: The refinement this request applies, if it is one.
    /// - Returns: The request's generation for `finishRequest(_:_:)`, or nil when a request is
    ///   already running.
    func beginRequest(refinement: Refinement? = nil) -> Int? {
        guard let generation = requests.begin() else { return nil }
        runningRefinement = refinement
        errorMessage = nil
        requestStartedAt = .now
        return generation
    }

    /// Runs the work of the request started as `generation` (see `RequestRunner.finish(_:_:)`)
    /// and shows a failure in the error banner. A cancelled or replaced request shows no error.
    /// Either way the monthly token count is read again, since the request may have used tokens.
    ///
    /// - Returns: The operation's value, or nil when it failed or was cancelled.
    func finishRequest<Value>(
        _ generation: Int, _ operation: () async throws(PolishError) -> Value
    ) async -> Value? {
        let outcome = await requests.finish(generation, operation)
        defer { refreshMonthlyUsage() }
        if !requests.isRunning {
            requestStartedAt = nil
            runningRefinement = nil
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
        let includesLearningSummary: Bool
        let generation: Int
    }

    /// A polish request's preview on screen and the result made from it.
    private struct ShownPreview {
        let request: PolishRequest
        var result: PolishResult
        var isTextComplete: Bool
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
        polishStage = .detectingLanguage
        nextPreviewAt = nil
        return PolishRequest(
            text: text, channel: channel, includesLearningSummary: includesLearningSummary,
            generation: generation)
    }

    /// Runs `request` and shows its result. Streamed previews show its stage and its polished
    /// text as it arrives (see `showPreview(_:for:)`). When the complete text was shown first,
    /// the final result only adds the learning summary: the output, which the user may have
    /// edited meanwhile, stays. History and the learning log are written once, when the request
    /// ends.
    private func polish(_ request: PolishRequest) async {
        let polisher = polisher
        let mailbox = PreviewMailbox()
        let onPreview: @Sendable (PolishPreview) -> Void = { [weak self] preview in
            guard mailbox.post(preview) else { return }
            Task { @MainActor in await self?.deliverPreview(from: mailbox, for: request) }
        }
        let polished = await finishRequest(request.generation) { () async throws(PolishError) in
            try await polisher.polish(
                text: request.text, channel: request.channel,
                includeLearningSummary: request.includesLearningSummary, onPreview: onPreview)
        }
        if !requests.isRunning {
            polishStage = nil
        }
        let preview = shownPreview?.request.generation == request.generation ? endPreview() : nil
        guard let polished else {
            if let preview { endWithoutResult(preview) }
            return
        }
        if preview?.isTextComplete == true {
            let keepsChanges = showsChanges
            result = polished
            showsChanges = keepsChanges
            recordHistory(polished, input: request.text, channel: request.channel)
            saveOutputToHistory()
        } else {
            result = polished
            output = Self.editorText(fromMarkdown: polished.polishedText)
            recordHistory(polished, input: request.text, channel: request.channel)
        }
        appendToLearningLog(polished, channel: request.channel)
    }

    /// Shows the newest preview in `mailbox`, first waiting until `nextPreviewAt`. Previews
    /// posted meanwhile replace the one waiting, so only the newest is shown.
    private func deliverPreview(from mailbox: PreviewMailbox, for request: PolishRequest) async {
        if let nextPreviewAt {
            try? await Task.sleep(until: nextPreviewAt, clock: .continuous)
        }
        guard let preview = mailbox.take() else { return }
        let started = ContinuousClock.now
        showPreview(preview, for: request)
        let cost = ContinuousClock.now - started
        nextPreviewAt = started + max(Self.previewInterval, cost * Self.previewCostFactor)
    }

    /// Shows what the reply of `request` has said so far: its stage, and its polished text while
    /// it streams in, read-only until complete. Once the text is complete, later previews only
    /// update the language, so the output the user may be editing stays. Ignored when the
    /// request is no longer running (it finished, failed or was cancelled).
    private func showPreview(_ preview: PolishPreview, for request: PolishRequest) {
        guard requests.isCurrent(request.generation) else { return }
        polishStage = PolishStage(preview, includesLearningSummary: request.includesLearningSummary)
        if shownPreview?.isTextComplete == true {
            updateLanguage(from: preview)
            return
        }
        guard let text = preview.polishedText, !text.isEmpty || preview.isTextComplete else {
            return
        }
        let shown = ShownPreview(
            request: request,
            result: PolishResult(
                polishedText: text,
                learningSummary: nil,
                detectedLanguage: preview.detectedLanguage ?? "Unknown",
                wasTranslated: preview.wasTranslated ?? false,
                modelUsed: ModelRouting.pickModel(for: request.text)
            ),
            isTextComplete: preview.isTextComplete
        )
        shownPreview = shown
        result = shown.result
        output = Self.editorText(fromMarkdown: text)
        isStreamingText = !shown.isTextComplete
        isAwaitingSummary = request.includesLearningSummary && !shown.result.wasTranslated
    }

    /// Takes the language of a preview that came after the complete text into the result on
    /// screen, for replies that write `polished_text` first. Keeps the output and Show changes.
    private func updateLanguage(from preview: PolishPreview) {
        guard var shown = shownPreview else { return }
        shown.result.detectedLanguage = preview.detectedLanguage ?? "Unknown"
        shown.result.wasTranslated = preview.wasTranslated ?? false
        guard shown.result != result else { return }
        shownPreview = shown
        let keepsChanges = showsChanges
        result = shown.result
        showsChanges = keepsChanges && !shown.result.wasTranslated
        isAwaitingSummary = shown.request.includesLearningSummary && !shown.result.wasTranslated
    }

    /// Forgets the shown preview, which stays on screen, and stops waiting for its summary.
    private func endPreview() -> ShownPreview? {
        let shown = shownPreview
        shownPreview = nil
        isAwaitingSummary = false
        isStreamingText = false
        return shown
    }

    /// Ends a preview whose request stopped without a final result. A complete text stays and is
    /// saved to history, with the output as edited; text that was still streaming in is removed.
    private func endWithoutResult(_ shown: ShownPreview) {
        if shown.isTextComplete {
            recordHistory(shown.result, input: shown.request.text, channel: shown.request.channel)
            saveOutputToHistory()
        } else {
            result = nil
            output = NSAttributedString()
        }
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
        saveOutputToHistory()
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
    /// The edited output is saved to history first. Ignored while the text is still streaming in.
    func copyResult() async {
        guard result != nil, !isStreamingText else { return }
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
