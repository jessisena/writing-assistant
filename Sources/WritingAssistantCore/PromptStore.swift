import Foundation

// Stub from Phase 0 — W3 replaces the body. Keep the public signatures.
public struct PromptStore: PromptStoring {
    /// The `Prompts` folder shipped in this module's resource bundle.
    public static var bundledDefaultsURL: URL {
        fatalError("unimplemented")
    }

    /// `~/Library/Application Support/Writing Assistant/prompts`, defaults from the bundle.
    public static func standard() -> PromptStore {
        fatalError("unimplemented")
    }

    public let directoryURL: URL

    public init(directoryURL: URL, defaultsURL: URL = PromptStore.bundledDefaultsURL) {
        fatalError("unimplemented")
    }

    public func fileURL(_ file: PromptFile) -> URL {
        fatalError("unimplemented")
    }

    public func seedMissingDefaults() throws {
        fatalError("unimplemented")
    }

    public func read(_ file: PromptFile) throws -> String {
        fatalError("unimplemented")
    }

    public func write(_ text: String, to file: PromptFile) throws {
        fatalError("unimplemented")
    }

    public func restoreDefault(_ file: PromptFile) throws {
        fatalError("unimplemented")
    }

    public func assemble(for channel: Channel) throws -> String {
        fatalError("unimplemented")
    }
}
