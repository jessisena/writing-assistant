import WritingAssistantCore

// Shorter calls for tests that don't care about the system prompt, watch the stream or change the
// summary setting.

extension ClaudeRunning {
    func run(
        systemPrompt: String = "system", input: String, model: String, timeout: Duration,
        onText: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws(PolishError) -> ClaudeReply {
        try await run(
            systemPrompt: systemPrompt, input: input, model: model, timeout: timeout,
            onText: onText)
    }
}

extension Polishing {
    func polish(text: String, channel: Channel) async throws(PolishError) -> PolishResult {
        try await polish(
            text: text, channel: channel, options: .english(summary: true), onPreview: { _ in })
    }
}

extension PolishOptions {
    /// Work mode with the given language policy and summary setting.
    static func english(summary: Bool) -> PolishOptions {
        PolishOptions(mode: .work, outputLanguage: .english, includesLearningSummary: summary)
    }

    static func sameAsInput(summary: Bool) -> PolishOptions {
        PolishOptions(
            mode: .personal, outputLanguage: .sameAsInput, includesLearningSummary: summary)
    }
}
