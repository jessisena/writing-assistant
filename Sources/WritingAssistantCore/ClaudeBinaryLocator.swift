import Foundation

/// Finds the `claude` executable for an app launched from Finder or the Dock, which gets a
/// minimal PATH. Nothing is cached, so installing claude takes effect without a restart.
public struct ClaudeBinaryLocator: Sendable {
    /// `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`.
    public static var defaultSearchDirectories: [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin"),
            URL(filePath: "/opt/homebrew/bin"),
            URL(filePath: "/usr/local/bin"),
        ]
    }

    static let binaryName = "claude"
    static let loginShellTimeout: Duration = .seconds(5)

    private let searchDirectories: [URL]
    private let useLoginShell: Bool

    /// Creates a locator.
    ///
    /// - Parameters:
    ///   - searchDirectories: Directories checked in order for an executable `claude`.
    ///   - useLoginShell: When no directory has it, ask `zsh -l` (the user's login PATH).
    public init(
        searchDirectories: [URL] = ClaudeBinaryLocator.defaultSearchDirectories,
        useLoginShell: Bool = true
    ) {
        self.searchDirectories = searchDirectories
        self.useLoginShell = useLoginShell
    }

    /// Returns the first executable `claude` in the search directories, then falls back to the
    /// login shell's `command -v claude`. Returns nil when neither finds an executable file.
    ///
    /// Blocks for up to five seconds when the login shell is consulted; call it off the main
    /// actor.
    public func locate() -> URL? {
        for directory in searchDirectories {
            let candidate = directory.appending(path: Self.binaryName)
            if Self.isExecutableFile(candidate) {
                return candidate
            }
        }
        return useLoginShell ? locateWithLoginShell() : nil
    }

    private func locateWithLoginShell() -> URL? {
        let outcome: SubprocessOutcome
        do {
            outcome = try Subprocess.run(
                SubprocessRequest(
                    executable: URL(filePath: "/bin/zsh"),
                    arguments: ["-lc", "command -v \(Self.binaryName)"],
                    environment: nil,
                    input: nil,
                    timeout: Self.loginShellTimeout
                ))
        } catch {
            claudeLogger.warning("Login shell lookup for claude failed: \(error, privacy: .public)")
            return nil
        }
        guard outcome.status == 0 else { return nil }
        let lastLine = String(decoding: outcome.stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let path = lastLine, path.hasPrefix("/") else { return nil }
        let candidate = URL(filePath: path)
        return Self.isExecutableFile(candidate) ? candidate : nil
    }

    static func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }
}
