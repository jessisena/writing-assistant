import Foundation

// Stub from Phase 0 — W1 replaces the body. Keep the public signatures.
public struct PolishService: Polishing {
    public static let maxInputLength = 20_000
    public static let defaultTimeout: Duration = .seconds(120)

    public init(
        runner: any ClaudeRunning,
        prompts: any PromptStoring,
        timeout: Duration = PolishService.defaultTimeout
    ) {
        fatalError("unimplemented")
    }

    public func polish(text: String, channel: Channel) async throws(PolishError) -> PolishResult {
        fatalError("unimplemented")
    }

    public func checkReady() async throws(PolishError) {
        fatalError("unimplemented")
    }
}
