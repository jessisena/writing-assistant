import Foundation

/// A prompt file operation that failed, with the file it was working on.
public struct PromptStoreError: LocalizedError, Sendable {
    public let operation: String
    public let path: String
    public let reason: String

    public var errorDescription: String? {
        "Couldn't \(operation) \(path): \(reason)"
    }
}

/// Prompt files stored on disk, seeded from the defaults bundled with this module.
///
/// Every read goes to disk with no caching, so edits made in the app or in any external editor
/// apply on the next request.
public struct PromptStore: PromptStoring {
    static let resourceBundleName = "WritingAssistant_WritingAssistantCore.bundle"

    /// The `Prompts` folder shipped in this module's resource bundle.
    ///
    /// The packaged app keeps the resource bundle in `Contents/Resources`, because codesign
    /// rejects unsealed content at the `.app` root. SwiftPM's `Bundle.module` only looks at that
    /// root and at an absolute `.build` path on the build machine, so the app's resources folder
    /// is checked first. `Bundle.module` covers `swift run` and the tests; it is only touched as
    /// the fallback because its accessor calls `fatalError` itself when it finds nothing.
    public static var bundledDefaultsURL: URL {
        let resolved = resolveDefaultsURL(mainResourcesURL: Bundle.main.resourceURL) {
            Bundle.module.url(forResource: "Prompts", withExtension: nil)
        }
        guard let resolved else {
            fatalError(
                "Bundled Prompts folder is missing from both \(resourceBundleName) in "
                    + "\(Bundle.main.bundlePath) and the SwiftPM module bundle. "
                    + "The WritingAssistantCore resource bundle was packaged incorrectly.")
        }
        return resolved
    }

    /// Picks `<mainResourcesURL>/<resource bundle>/Prompts` when it exists, else `moduleDefaults`.
    static func resolveDefaultsURL(
        mainResourcesURL: URL?, moduleDefaults: () -> URL?
    ) -> URL? {
        if let mainResourcesURL {
            let packaged =
                mainResourcesURL
                .appending(path: resourceBundleName, directoryHint: .isDirectory)
                .appending(path: "Prompts", directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            let path = packaged.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                return packaged
            }
        }
        return moduleDefaults()
    }

    /// `~/Library/Application Support/Writing Assistant/prompts`, defaults from the bundle.
    public static func standard() -> PromptStore {
        let directory = URL.applicationSupportDirectory
            .appending(path: "Writing Assistant", directoryHint: .isDirectory)
            .appending(path: "prompts", directoryHint: .isDirectory)
        return PromptStore(directoryURL: directory)
    }

    public let directoryURL: URL
    private let defaultsURL: URL

    /// Creates a store rooted at `directoryURL`.
    ///
    /// Args:
    ///   directoryURL: Folder holding the editable prompt files.
    ///   defaultsURL: Folder holding the default prompt files, laid out like `directoryURL`.
    public init(directoryURL: URL, defaultsURL: URL = PromptStore.bundledDefaultsURL) {
        self.directoryURL = directoryURL
        self.defaultsURL = defaultsURL
    }

    public func fileURL(_ file: PromptFile) -> URL {
        directoryURL.appending(path: file.relativePath, directoryHint: .notDirectory)
    }

    /// Copies the bundled default for every prompt file that doesn't exist yet.
    ///
    /// Existing files are never touched, even when empty.
    ///
    /// Throws:
    ///   PromptStoreError: A directory couldn't be created or a default couldn't be copied.
    public func seedMissingDefaults() throws {
        let fileManager = FileManager.default
        for file in PromptFile.allCases {
            let destination = fileURL(file)
            guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
                continue
            }
            try createParentDirectory(of: destination)
            try perform("seed", destination) {
                try fileManager.copyItem(at: defaultURL(file), to: destination)
            }
        }
    }

    /// Reads a prompt file from disk as UTF-8.
    ///
    /// Throws:
    ///   PromptStoreError: The file is missing or isn't valid UTF-8.
    public func read(_ file: PromptFile) throws -> String {
        let url = fileURL(file)
        return try perform("read", url) { try String(contentsOf: url, encoding: .utf8) }
    }

    /// Validates `text` and atomically writes it as UTF-8, creating directories as needed.
    ///
    /// Throws:
    ///   PromptValidationError: `text` breaks a rule in `PromptFile.validate`; nothing is written.
    ///   PromptStoreError: The file couldn't be written.
    public func write(_ text: String, to file: PromptFile) throws {
        try file.validate(text)
        try save(text, to: fileURL(file))
    }

    /// Overwrites one prompt file with its bundled default.
    ///
    /// Throws:
    ///   PromptStoreError: The default couldn't be read or the file couldn't be written.
    public func restoreDefault(_ file: PromptFile) throws {
        let source = defaultURL(file)
        let text = try perform("read default", source) {
            try String(contentsOf: source, encoding: .utf8)
        }
        try save(text, to: fileURL(file))
    }

    /// Builds the system prompt for `channel`.
    ///
    /// Returns the trimmed global rules with `PromptFile.channelPlaceholder` replaced by the
    /// trimmed channel guidelines.
    ///
    /// Throws:
    ///   PromptStoreError: Either prompt file couldn't be read.
    public func assemble(for channel: Channel) throws -> String {
        let global = try read(.global).trimmingCharacters(in: .whitespacesAndNewlines)
        let guidelines = try read(.channel(channel))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return global.replacingOccurrences(of: PromptFile.channelPlaceholder, with: guidelines)
    }

    private func defaultURL(_ file: PromptFile) -> URL {
        defaultsURL.appending(path: file.relativePath, directoryHint: .notDirectory)
    }

    private func save(_ text: String, to url: URL) throws {
        try createParentDirectory(of: url)
        try perform("write", url) { try text.write(to: url, atomically: true, encoding: .utf8) }
    }

    private func createParentDirectory(of url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try perform("create the folder for", url) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func perform<T>(_ operation: String, _ url: URL, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw PromptStoreError(
                operation: operation,
                path: url.path(percentEncoded: false),
                reason: error.localizedDescription)
        }
    }
}
