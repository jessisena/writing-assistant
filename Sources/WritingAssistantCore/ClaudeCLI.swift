import Foundation
import os

let claudeLogger = Logger(subsystem: "local.writing-assistant", category: "claude-cli")

/// Runs prompts through the local `claude` CLI, authenticated by the user's Claude subscription.
///
/// Each call is a throwaway headless invocation: MCP servers and session persistence are off,
/// `ANTHROPIC_API_KEY` is removed so the subscription is used, and extended thinking is
/// disabled. The blocking process work runs on a GCD queue, not Swift's cooperative pool.
/// A found binary is cached per instance (and copies of it) until it stops being executable.
public struct ClaudeCLI: ClaudeRunning {
    static let headlessFlags = [
        "--strict-mcp-config",
        "--mcp-config",
        #"{"mcpServers":{}}"#,
        "--no-session-persistence",
    ]
    static let maxAttempts = 2
    /// CLI output can echo the user's text, so failure details are capped before logging.
    static let maxFailureDetailLength = 500
    static let cancelledDetail = "Cancelled"

    private let locator: ClaudeBinaryLocator
    private let cache = BinaryLocationCache()

    /// Creates a runner that resolves the binary with `locator`, caching a successful lookup.
    public init(locator: ClaudeBinaryLocator = ClaudeBinaryLocator()) {
        self.locator = locator
    }

    /// Sends `prompt` on stdin to `claude --print` and returns its trimmed stdout.
    ///
    /// A non-zero exit is retried once; a timeout is never retried. Cancelling the calling task
    /// terminates the process (SIGTERM, then SIGKILL after a grace period).
    ///
    /// - Parameters:
    ///   - prompt: Full prompt text written to the CLI's stdin.
    ///   - model: Value passed to `--model`.
    ///   - timeout: Limit for each attempt; the process is terminated when it is exceeded.
    /// - Throws: `PolishError.claudeNotFound`, `.timeout(seconds:)`, or `.cliFailed(stderr:)`
    ///   (`"Cancelled"` when the task is cancelled or `terminateRunningProcesses()` is called).
    public func run(prompt: String, model: String, timeout: Duration) async throws(PolishError)
        -> String
    {
        let invocation = Invocation(
            locator: locator, cache: cache, prompt: prompt, model: model, timeout: timeout)
        let control = SubprocessControl()
        let result = await withTaskCancellationHandler {
            await Self.offCooperativePool { Self.runBlocking(invocation, control: control) }
        } onCancel: {
            control.cancel()
        }
        return try result.get()
    }

    /// Throws `PolishError.claudeNotFound` when the CLI can't be located.
    public func checkAvailable() async throws(PolishError) {
        let locator = self.locator
        let cache = self.cache
        let found = await Self.offCooperativePool { cache.resolve(with: locator) != nil }
        if !found {
            throw .claudeNotFound
        }
    }

    /// Terminates every claude process started by any `ClaudeCLI` that is still running.
    /// Call it when the app quits so no child outlives it. Their `run` calls throw
    /// `.cliFailed(stderr: "Cancelled")`.
    public static func terminateRunningProcesses() {
        SubprocessControl.cancelAll()
    }

    struct Invocation: Sendable {
        let locator: ClaudeBinaryLocator
        let cache: BinaryLocationCache
        let prompt: String
        let model: String
        let timeout: Duration
    }

    static func runBlocking(_ invocation: Invocation, control: SubprocessControl)
        -> Result<String, PolishError>
    {
        control.register()
        defer { control.unregister() }
        guard let binary = invocation.cache.resolve(with: invocation.locator) else {
            return .failure(.claudeNotFound)
        }
        let request = SubprocessRequest(
            executable: binary,
            arguments: ["--print", "--output-format", "text", "--model", invocation.model]
                + headlessFlags,
            environment: makeEnvironment(binaryDirectory: binary.deletingLastPathComponent()),
            input: Data(invocation.prompt.utf8),
            timeout: invocation.timeout
        )
        var lastFailure = ""
        for attempt in 1...maxAttempts {
            let outcome: SubprocessOutcome
            do {
                outcome = try Subprocess.run(request, control: control)
            } catch {
                return .failure(mapSubprocessError(error, timeout: invocation.timeout))
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
        return capped(stderr.isEmpty ? trimmed(outcome.stdout) : stderr)
    }

    static func capped(_ detail: String) -> String {
        guard detail.count > maxFailureDetailLength else { return detail }
        return String(detail.prefix(maxFailureDetailLength)) + "… (truncated)"
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
        case .cancelled:
            claudeLogger.info("claude CLI run was cancelled")
            return .cliFailed(stderr: cancelledDetail)
        case .launchFailed:
            claudeLogger.error("\(error.description, privacy: .public)")
            return .cliFailed(stderr: capped(error.description))
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

/// Remembers the last successful lookup. A cached path that is no longer an executable file is
/// looked up again, so reinstalling or moving claude works without restarting the app.
final class BinaryLocationCache: Sendable {
    private let cached = OSAllocatedUnfairLock<URL?>(initialState: nil)

    func resolve(with locator: ClaudeBinaryLocator) -> URL? {
        if let url = cached.withLock({ $0 }), ClaudeBinaryLocator.isExecutableFile(url) {
            return url
        }
        let found = locator.locate()
        cached.withLock { $0 = found }
        return found
    }
}

struct SubprocessRequest: Sendable {
    /// Absolute URL of the program.
    let executable: URL
    let arguments: [String]
    /// Full environment, or nil to inherit the current one.
    let environment: [String: String]?
    /// Bytes written to stdin before it is closed; nil connects stdin to /dev/null.
    let input: Data?
    /// Limit for the process to exit and close its output.
    let timeout: Duration
}

struct SubprocessOutcome: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

enum SubprocessError: Error, CustomStringConvertible {
    case launchFailed(executable: String, reason: String)
    case timedOut
    case cancelled

    var description: String {
        switch self {
        case .launchFailed(let executable, let reason):
            "Couldn't launch \(executable): \(reason)"
        case .timedOut:
            "Process timed out"
        case .cancelled:
            "Process was cancelled"
        }
    }
}

/// Lets another thread stop a run: cancellation of the calling task, or app shutdown through
/// `cancelAll()`. Once cancelled it stays cancelled, so a retry can't start a new process.
final class SubprocessControl: Sendable {
    private struct State: Sendable {
        var isCancelled = false
        var process: Process?
    }

    private static let registered = OSAllocatedUnfairLock(
        initialState: [ObjectIdentifier: SubprocessControl]())
    private let state = OSAllocatedUnfairLock(initialState: State())

    var isCancelled: Bool { state.withLock { $0.isCancelled } }

    static func cancelAll() {
        let controls = registered.withLock { Array($0.values) }
        for control in controls {
            control.cancel()
        }
    }

    func register() {
        Self.registered.withLock { $0[ObjectIdentifier(self)] = self }
    }

    func unregister() {
        _ = Self.registered.withLock { $0.removeValue(forKey: ObjectIdentifier(self)) }
    }

    func cancel() {
        let process = state.withLock { state in
            state.isCancelled = true
            return state.process
        }
        if let process {
            Subprocess.requestTermination(process)
        }
    }

    /// Tracks `process` so `cancel()` can stop it. Returns true when already cancelled, in
    /// which case the caller must stop the process itself.
    func attach(_ process: Process) -> Bool {
        state.withLock { state in
            state.process = process
            return state.isCancelled
        }
    }

    func detach() {
        state.withLock { $0.process = nil }
    }
}

/// Synchronous process execution with concurrent stdout/stderr draining and a hard timeout.
enum Subprocess {
    static let terminationGrace: Duration = .seconds(2)

    /// Runs the request to completion, blocking the calling thread. The child runs in the
    /// temporary directory.
    ///
    /// - Parameters:
    ///   - request: What to run. On timeout the process gets SIGTERM, then SIGKILL after
    ///     `terminationGrace`.
    ///   - control: Lets another thread cancel the run the same way.
    /// - Throws: `SubprocessError.launchFailed`, `.timedOut`, or `.cancelled`.
    static func run(_ request: SubprocessRequest, control: SubprocessControl? = nil)
        throws(SubprocessError) -> SubprocessOutcome
    {
        if control?.isCancelled == true {
            throw .cancelled
        }
        let deadline = DispatchTime.now() + dispatchInterval(request.timeout)
        let child = try LaunchedProcess(request)
        defer { control?.detach() }
        if control?.attach(child.process) == true {
            requestTermination(child.process)
        }
        if let input = request.input {
            feed(input, to: child.stdin)
        }
        return try child.awaitCompletion(until: deadline, control: control)
    }

    /// Sends SIGTERM now and SIGKILL after `terminationGrace` if the process is still alive.
    static func requestTermination(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + dispatchInterval(terminationGrace)) {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
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

    static func dispatchInterval(_ duration: Duration) -> DispatchTimeInterval {
        let (seconds, attoseconds) = duration.components
        let cappedSeconds = min(max(seconds, 0), Int64(Int32.max))
        return .nanoseconds(Int(cappedSeconds * 1_000_000_000 + attoseconds / 1_000_000_000))
    }
}

/// A started child process with its output being drained.
private struct LaunchedProcess {
    let process = Process()
    let stdout = OutputCollector()
    let stderr = OutputCollector()
    private let stdinPipe = Pipe()
    private let exited = DispatchSemaphore(value: 0)

    var stdin: FileHandle { stdinPipe.fileHandleForWriting }

    init(_ request: SubprocessRequest) throws(SubprocessError) {
        process.executableURL = request.executable
        process.arguments = request.arguments
        // A neutral cwd keeps claude from picking up the caller's project context.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        if let environment = request.environment {
            process.environment = environment
        }
        process.standardInput = request.input == nil ? FileHandle.nullDevice : stdinPipe
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe
        let exited = self.exited
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw .launchFailed(
                executable: request.executable.path, reason: error.localizedDescription)
        }
        stdout.startDraining()
        stderr.startDraining()
    }

    func awaitCompletion(until deadline: DispatchTime, control: SubprocessControl?)
        throws(SubprocessError) -> SubprocessOutcome
    {
        let exitedInTime = exited.wait(timeout: deadline) == .success
        let finished =
            exitedInTime && control?.isCancelled != true
            && stdout.waitForEndOfFile(until: deadline)
            && stderr.waitForEndOfFile(until: deadline)
        guard finished else {
            if !exitedInTime {
                Subprocess.requestTermination(process)
                exited.wait()
            }
            stdout.stopDraining()
            stderr.stopDraining()
            throw control?.isCancelled == true ? .cancelled : .timedOut
        }
        return SubprocessOutcome(
            status: process.terminationStatus, stdout: stdout.data, stderr: stderr.data)
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
