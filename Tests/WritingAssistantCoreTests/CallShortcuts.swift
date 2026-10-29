import WritingAssistantCore

// Shorter calls for tests that don't watch the stream or change the summary setting.

extension ClaudeRunning {
    func run(prompt: String, model: String, timeout: Duration) async throws(PolishError)
        -> ClaudeReply
    {
        try await run(prompt: prompt, model: model, timeout: timeout, onText: { _ in })
    }
}

extension Polishing {
    func polish(text: String, channel: Channel) async throws(PolishError) -> PolishResult {
        try await polish(
            text: text, channel: channel, includeLearningSummary: true, onPreview: { _ in })
    }
}
