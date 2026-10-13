import Foundation

// Stub from Phase 0 — W2 replaces the body. Keep the public signatures.
public struct ClaudeBinaryLocator: Sendable {
    /// `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`.
    public static var defaultSearchDirectories: [URL] {
        fatalError("unimplemented")
    }

    public init(
        searchDirectories: [URL] = ClaudeBinaryLocator.defaultSearchDirectories,
        useLoginShell: Bool = true
    ) {
        fatalError("unimplemented")
    }

    public func locate() -> URL? {
        fatalError("unimplemented")
    }
}
