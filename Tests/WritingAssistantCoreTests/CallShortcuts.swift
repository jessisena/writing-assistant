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
            text: text, channel: channel, includeLearningSummary: true, onPreview: { _ in })
    }
}
