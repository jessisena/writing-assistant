import Foundation

// Stub from Phase 0 — W1 replaces the body. Keep the public signatures.
public enum ModelRouting {
    public static let haikuModel = "claude-haiku-4-5-20251001"
    public static let sonnetModel = "claude-sonnet-4-6"

    public static func pickModel(for text: String) -> String {
        fatalError("unimplemented")
    }
}
