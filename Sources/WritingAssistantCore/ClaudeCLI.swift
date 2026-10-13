import Foundation
import os

let claudeLogger = Logger(subsystem: "local.writing-assistant", category: "claude-cli")

/// Runs prompts through the local `claude` CLI, authenticated by the user's Claude subscription.
///
/// Each call is a throwaway headless invocation: MCP servers and session persistence are off,
/// `ANTHROPIC_API_KEY` is removed so the subscription is used, and extended thinking is
/// disabled. The blocking process work runs on a GCD queue, not Swift's cooperative pool.
public struct ClaudeCLI: ClaudeRunning {
    static let headlessFlags = [
        "--strict-mcp-config",
        "--mcp-config",
        #"{"mcpServers":{}}"#,
        "--no-session-persistence",
    ]
    static let maxAttempts = 2

    private let locator: ClaudeBinaryLocator

    /// Creates a runner that resolves the binary with `locator` on every call.
    public init(locator: ClaudeBinaryLocator = ClaudeBinaryLocator()) {
        self.locator = locator
    }

    /// Sends `prompt` on stdin to `claude --print` and returns its trimmed stdout.
    ///
    /// A non-zero exit is retried once; a timeout is never retried.
    ///
    /// - Parameters:
    ///   - prompt: Full prompt text written to the CLI's stdin.
    ///   - model: Value passed to `--model`.
    ///   - timeout: Limit for each attempt; the process is terminated when it is exceeded.
    /// - Throws: `PolishError.claudeNotFound`, `.timeout(seconds:)`, or `.cliFailed(stderr:)`.
    public func run(prompt: String, model: String, timeout: Duration) async throws(PolishError)
        -> String
    {
        let locator = self.locator
        let result = await Self.offCooperativePool {
            Self.runBlocking(locator: locator, prompt: prompt, model: model, timeout: timeout)
        }
        return try result.get()
    }

    /// Throws `PolishError.claudeNotFound` when the CLI can't be located.
    public func checkAvailable() async throws(PolishError) {
        let locator = self.locator
        let found = await Self.offCooperativePool { locator.locate() != nil }
        if !found {
            throw .claudeNotFound
        }
    }

    static func runBlocking(
        locator: ClaudeBinaryLocator, prompt: String, model: String, timeout: Duration
    ) -> Result<String, PolishError> {
        guard let binary = locator.locate() else {
            return .failure(.claudeNotFound)
        }
        let arguments = ["--print", "--output-format", "text", "--model", model] + headlessFlags
        let environment = makeEnvironment(binaryDirectory: binary.deletingLastPathComponent())
        var lastFailure = ""
        for attempt in 1...maxAttempts {
            let outcome: SubprocessOutcome
            do {
                outcome = try Subprocess.run(
                    executable: binary,
                    arguments: arguments,
                    environment: environment,
                    input: Data(prompt.utf8),
                    timeout: timeout
                )
            } catch {
                return .failure(mapSubprocessError(error, timeout: timeout))
            }
            if outcome.status == 0 {
                return .success(trimmed(outcome.stdout))
            }
            lastFailure = failureDetail(outcome)
            claudeLogger.error(
                """
                claude CLI exited with status \(outcome.status) \
                (attempt \(attempt) of \(maxAttempts)): \(lastFailure, privacy: .public)
                """)
        }
        return .failure(.cliFailed(stderr: lastFailure))
    }

    /// claude reports some failures (e.g. "Not logged in") on stdout, so fall back to it.
    private static func failureDetail(_ outcome: SubprocessOutcome) -> String {
        let stderr = trimmed(outcome.stderr)
        return stderr.isEmpty ? trimmed(outcome.stdout) : stderr
    }

    static func makeEnvironment(binaryDirectory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // claude needs USER to find its keychain login; Finder launches can lack it.
        if environment["USER", default: ""].isEmpty {
            environment["USER"] = NSUserName()
        }
        if environment["HOME", default: ""].isEmpty {
            environment["HOME"] = NSHomeDirectory()
        }
        environment["ANTHROPIC_API_KEY"] = nil
        environment["MAX_THINKING_TOKENS"] = "0"
        environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        var searchPath = ([binaryDirectory] + ClaudeBinaryLocator.defaultSearchDirectories)
            .map(\.path)
        if let inherited = environment["PATH"], !inherited.isEmpty {
            searchPath.append(inherited)
        }
        environment["PATH"] = searchPath.joined(separator: ":")
        return environment
    }

    private static func mapSubprocessError(_ error: SubprocessError, timeout: Duration)
        -> PolishError
    {
        switch error {
        case .timedOut:
            claudeLogger.error("claude CLI timed out after \(timeout, privacy: .public)")
            return .timeout(seconds: Int(timeout.components.seconds))
        case .launchFailed:
            claudeLogger.error("\(error.description, privacy: .public)")
            return .cliFailed(stderr: error.description)
        }
    }

    private static func trimmed(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func offCooperativePool<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}

struct SubprocessOutcome: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

enum SubprocessError: Error, CustomStringConvertible {
    case launchFailed(executable: String, reason: String)
    case timedOut

    var description: String {
        switch self {
        case .launchFailed(let executable, let reason):
            "Couldn't launch \(executable): \(reason)"
        case .timedOut:
            "Process timed out"
        }
    }
}

/// Synchronous process execution with concurrent stdout/stderr draining and a hard timeout.
enum Subprocess {
    static let terminationGrace: Duration = .seconds(2)

    /// Runs `executable` to completion, blocking the calling thread.
    ///
    /// - Parameters:
    ///   - executable: Absolute URL of the program.
    ///   - arguments: Arguments passed to the program.
    ///   - environment: Full environment, or nil to inherit the current one.
    ///   - input: Bytes written to stdin before it is closed; nil connects stdin to /dev/null.
    ///   - timeout: Limit for the process to exit and close its output. On expiry the process
    ///     gets SIGTERM, then SIGKILL after `terminationGrace`.
    /// - Throws: `SubprocessError.launchFailed` or `.timedOut`.
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        input: Data?,
        timeout: Duration
    ) throws(SubprocessError) -> SubprocessOutcome {
        let deadline = DispatchTime.now() + dispatchInterval(timeout)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // A neutral cwd keeps claude from picking up the caller's project context.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        if let environment {
            process.environment = environment
        }
        let stdinPipe = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdinPipe
        let stdout = OutputCollector()
        let stderr = OutputCollector()
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw .launchFailed(executable: executable.path, reason: error.localizedDescription)
        }
        stdout.startDraining()
        stderr.startDraining()
        if let input {
            feed(input, to: stdinPipe.fileHandleForWriting)
        }

        let finished =
            exited.wait(timeout: deadline) == .success
            && stdout.waitForEndOfFile(until: deadline)
            && stderr.waitForEndOfFile(until: deadline)
        guard finished else {
            stop(process, exited: exited)
            stdout.stopDraining()
            stderr.stopDraining()
            throw .timedOut
        }
        return SubprocessOutcome(
            status: process.terminationStatus, stdout: stdout.data, stderr: stderr.data)
    }

    private static func feed(_ input: Data, to handle: FileHandle) {
        // A child that exits without reading stdin must surface as EPIPE, not kill the app.
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handle.write(contentsOf: input)
            } catch {
                claudeLogger.debug("stdin closed before the prompt was fully written: \(error)")
            }
            do {
                try handle.close()
            } catch {
                claudeLogger.debug("Couldn't close stdin: \(error)")
            }
        }
    }

    private static func stop(_ process: Process, exited: DispatchSemaphore) {
        guard process.isRunning else { return }
        process.terminate()
        if exited.wait(timeout: .now() + dispatchInterval(terminationGrace)) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            exited.wait()
        }
    }

    private static func dispatchInterval(_ duration: Duration) -> DispatchTimeInterval {
        let (seconds, attoseconds) = duration.components
        let cappedSeconds = min(max(seconds, 0), Int64(Int32.max))
        return .nanoseconds(Int(cappedSeconds * 1_000_000_000 + attoseconds / 1_000_000_000))
    }
}

/// Collects one output pipe without blocking a thread, so large output can't fill the pipe
/// buffer and deadlock the child.
private final class OutputCollector: Sendable {
    let pipe = Pipe()
    private let buffer = OSAllocatedUnfairLock(initialState: Data())
    private let reachedEndOfFile = DispatchSemaphore(value: 0)

    var data: Data { buffer.withLock { $0 } }

    func startDraining() {
        pipe.fileHandleForReading.readabilityHandler = { [buffer, reachedEndOfFile] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                reachedEndOfFile.signal()
            } else {
                buffer.withLock { $0.append(chunk) }
            }
        }
    }

    func waitForEndOfFile(until deadline: DispatchTime) -> Bool {
        reachedEndOfFile.wait(timeout: deadline) == .success
    }

    func stopDraining() {
        pipe.fileHandleForReading.readabilityHandler = nil
    }
}
