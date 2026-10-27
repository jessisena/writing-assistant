import CryptoKit
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
    /// - Parameters:
    ///   - directoryURL: Folder holding the editable prompt files.
    ///   - defaultsURL: Folder holding the default prompt files, laid out like `directoryURL`.
    public init(directoryURL: URL, defaultsURL: URL = PromptStore.bundledDefaultsURL) {
        self.directoryURL = directoryURL
        self.defaultsURL = defaultsURL
    }

    public func fileURL(_ file: PromptFile) -> URL {
        directoryURL.appending(path: file.relativePath, directoryHint: .notDirectory)
    }

    /// Copies the bundled default for every prompt file that doesn't exist yet.
    ///
    /// Existing files are never touched, even when empty. Files are seeded in
    /// `PromptFile.allCases` order and seeding stops at the first failure: files seeded before it
    /// stay in place, and calling this again seeds the rest once the cause is fixed. Each seeded
    /// file's default hash is recorded in the manifest that `syncDefaults()` compares against.
    ///
    /// - Throws: `PromptStoreError` naming the first file whose folder couldn't be created or
    ///   whose default couldn't be copied, or the manifest when it couldn't be read or written.
    public func seedMissingDefaults() throws {
        let fileManager = FileManager.default
        var manifest: [String: String]?
        for file in PromptFile.allCases {
            let destination = fileURL(file)
            guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
                continue
            }
            var entries = try manifest ?? loadManifest()
            let data = try readDefault(file)
            try createParentDirectory(of: destination)
            try perform("seed", destination) { try data.write(to: destination, options: .atomic) }
            entries[file.relativePath] = Self.hash(data)
            try saveManifest(entries)
            manifest = entries
        }
    }

    /// Brings changed bundled defaults to the prompt files on disk.
    ///
    /// For each existing file whose bundled default differs from the one recorded in the
    /// manifest, a file still matching its recorded default is overwritten with the new default,
    /// and an edited file is left alone and returned. A file with no manifest entry (installs
    /// from before the manifest existed) is recorded when it matches the bundled default and
    /// returned otherwise. A manifest that can't be decoded is treated as missing and rewritten.
    ///
    /// - Returns: Edited files whose bundled default is newer than the one the user started from.
    /// - Throws: `PromptStoreError` when a prompt file, its default or the manifest couldn't be
    ///   read or written.
    public func syncDefaults() throws -> Set<PromptFile> {
        var manifest = try loadManifest()
        var newer = Set<PromptFile>()
        for file in PromptFile.allCases {
            let url = fileURL(file)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            if try !sync(file, manifest: &manifest) {
                newer.insert(file)
            }
        }
        try saveManifest(manifest)
        return newer
    }

    /// Records the current bundled default as seen, without changing the file ("Keep mine").
    ///
    /// - Throws: `PromptStoreError` when the default couldn't be read or the manifest couldn't be
    ///   read or written.
    public func acknowledgeDefault(_ file: PromptFile) throws {
        var manifest = try loadManifest()
        manifest[file.relativePath] = Self.hash(try readDefault(file))
        try saveManifest(manifest)
    }

    /// Reads a prompt file from disk as UTF-8.
    ///
    /// - Throws: `PromptStoreError` when the file is missing or isn't valid UTF-8.
    public func read(_ file: PromptFile) throws -> String {
        let url = fileURL(file)
        return try perform("read", url) { try String(contentsOf: url, encoding: .utf8) }
    }

    /// Validates `text` and atomically writes it as UTF-8, creating directories as needed.
    ///
    /// - Throws: `PromptValidationError` when `text` breaks a rule in `PromptFile.validate`, in
    ///   which case nothing is written; `PromptStoreError` when the file couldn't be written.
    public func write(_ text: String, to file: PromptFile) throws {
        try file.validate(text)
        try save(text, to: fileURL(file))
    }

    /// Overwrites one prompt file with its bundled default and records it in the manifest.
    ///
    /// - Throws: `PromptStoreError` when the default couldn't be read or the file or manifest
    ///   couldn't be written.
    public func restoreDefault(_ file: PromptFile) throws {
        let data = try readDefault(file)
        let destination = fileURL(file)
        try createParentDirectory(of: destination)
        try perform("write", destination) { try data.write(to: destination, options: .atomic) }
        var manifest = try loadManifest()
        manifest[file.relativePath] = Self.hash(data)
        try saveManifest(manifest)
    }

    /// Builds the system prompt for `channel`.
    ///
    /// Returns the trimmed global rules with `PromptFile.channelPlaceholder` replaced by the
    /// trimmed channel guidelines.
    ///
    /// - Throws: `PromptStoreError` when either prompt file couldn't be read.
    public func assemble(for channel: Channel) throws -> String {
        let global = try read(.global).trimmingCharacters(in: .whitespacesAndNewlines)
        let guidelines = try read(.channel(channel))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return global.replacingOccurrences(of: PromptFile.channelPlaceholder, with: guidelines)
    }

    private func defaultURL(_ file: PromptFile) -> URL {
        defaultsURL.appending(path: file.relativePath, directoryHint: .notDirectory)
    }

    /// Applies the `syncDefaults()` rules to one existing file. Returns false when the user's
    /// edited copy is kept despite a newer bundled default.
    private func sync(_ file: PromptFile, manifest: inout [String: String]) throws -> Bool {
        let key = file.relativePath
        let defaultData = try readDefault(file)
        let bundled = Self.hash(defaultData)
        let recorded = manifest[key]
        guard recorded != bundled else { return true }
        let url = fileURL(file)
        let current = Self.hash(try perform("read", url) { try Data(contentsOf: url) })
        if current == bundled {
            manifest[key] = bundled
            return true
        }
        guard let recorded, current == recorded else { return false }
        try perform("update", url) { try defaultData.write(to: url, options: .atomic) }
        manifest[key] = bundled
        return true
    }

    private func readDefault(_ file: PromptFile) throws -> Data {
        let source = defaultURL(file)
        return try perform("read default", source) { try Data(contentsOf: source) }
    }

    /// `prompts/.defaults.json`: each `relativePath` mapped to the SHA-256 hex of the default the
    /// file was last seeded, restored or updated from, or that the user acknowledged.
    private var manifestURL: URL {
        directoryURL.appending(path: ".defaults.json", directoryHint: .notDirectory)
    }

    /// A missing or undecodable manifest reads as empty, so every file is checked afresh.
    private func loadManifest() throws -> [String: String] {
        let url = manifestURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return [:]
        }
        let data = try perform("read", url) { try Data(contentsOf: url) }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveManifest(_ manifest: [String: String]) throws {
        let url = manifestURL
        try createParentDirectory(of: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try perform("write", url) { try encoder.encode(manifest).write(to: url, options: .atomic) }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
