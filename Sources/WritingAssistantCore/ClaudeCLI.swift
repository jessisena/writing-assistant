import Foundation

// Stub from Phase 0 — W2 replaces the body. Keep the public signatures.
public struct ClaudeCLI: ClaudeRunning {
    public init(locator: ClaudeBinaryLocator = ClaudeBinaryLocator()) {
        fatalError("unimplemented")
    }

    public func run(prompt: String, model: String, timeout: Duration) async throws(PolishError)
        -> String
    {
        fatalError("unimplemented")
    }

    public func checkAvailable() async throws(PolishError) {
        fatalError("unimplemented")
    }
}
