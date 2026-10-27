import AppKit
import Observation
import WritingAssistantCore

/// State and actions for the main window.
@Observable @MainActor final class AppModel {
    static let copiedDuration: Duration = .seconds(2)

    var inputText = ""
    var channel: Channel = .formal
    private(set) var isLoading = false
    private(set) var result: PolishResult?
    private(set) var errorMessage: String?
    private(set) var copied = false

    @ObservationIgnored private let polisher: any Polishing
    @ObservationIgnored private let writeToPasteboard: @MainActor (String) -> Void
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private var copyGeneration = 0
    @ObservationIgnored private var startupErrorMessage: String?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - polisher: Service that polishes text.
    ///   - writeToPasteboard: Puts text on the clipboard. Defaults to the general pasteboard.
    ///   - sleep: Waits before the "Copied" label resets. Defaults to `Task.sleep`.
    init(
        polisher: any Polishing,
        writeToPasteboard: @escaping @MainActor (String) -> Void =
            AppModel.writeToGeneralPasteboard,
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.polisher = polisher
        self.writeToPasteboard = writeToPasteboard
        self.sleep = sleep
    }

    /// Polishes `inputText` with the selected channel. Ignored while a request is running.
    func process() async {
        guard !isLoading else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = PolishError.emptyInput.errorDescription
            return
        }
        errorMessage = nil
        result = nil
        isLoading = true
        defer { isLoading = false }
        do {
            result = try await polisher.polish(text: text, channel: channel)
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

    /// Copies the polished text and shows "Copied" for `copiedDuration`.
    func copyResult() async {
        guard let text = result?.polishedText else { return }
        writeToPasteboard(text)
        copied = true
        copyGeneration += 1
        let generation = copyGeneration
        await sleep(Self.copiedDuration)
        if generation == copyGeneration {
            copied = false
        }
    }

    static func writeToGeneralPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
