import Foundation
import Testing
import WritingAssistantCore

/// A temporary directory holding a fake `claude` shell script. The script can write files next
/// to itself (`$DIR`) so tests can inspect what the real process received.
private struct FakeClaude {
    let directory: URL
    private let fileContents: String
    private let executable: Bool

    init(script: String, executable: Bool = true) throws {
        try self.init(
            contents: "#!/bin/sh\nDIR=\"$(dirname \"$0\")\"\n\(script)\n", executable: executable)
    }

    /// A `claude` file with exactly `contents`, e.g. a script with a broken shebang.
    init(contents: String, executable: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "ClaudeCLITests-\(UUID().uuidString)")
        fileContents = contents
        self.executable = executable
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try install()
    }

    var binary: URL { directory.appending(path: "claude") }

    func install() throws {
        try fileContents.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: binary.path)
    }

    func uninstall() throws {
        try FileManager.default.removeItem(at: binary)
    }

    var cli: ClaudeCLI {
        ClaudeCLI(
            locator: ClaudeBinaryLocator(searchDirectories: [directory], useLoginShell: false))
    }

    func contents(of name: String) throws -> String {
        try String(contentsOf: directory.appending(path: name), encoding: .utf8)
    }

    func invocationCount() throws -> Int {
        try contents(of: "count").split(separator: "\n").count
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension FakeClaude {
    /// The child's environment as recorded by `env > "$DIR/env"`. Assertions look up single
    /// keys so a failure never prints the whole environment (which can hold tokens).
    func recordedEnvironment() throws -> [String: String] {
        var environment: [String: String] = [:]
        for line in try contents(of: "env").split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                environment[String(parts[0])] = String(parts[1])
            }
        }
        return environment
    }
}

private let countInvocation = #"echo x >> "$DIR/count""#

/// Applies `overrides` to this process's environment (nil unsets) for the duration of `body`.
/// Callers must be in a `.serialized` suite.
private func withEnvironment(
    _ overrides: [String: String?], body: () async throws -> Void
) async rethrows {
    let environment = ProcessInfo.processInfo.environment
    let previous = overrides.keys.map { ($0, environment[$0]) }
    defer { previous.forEach(setEnvironment) }
    overrides.forEach(setEnvironment)
    try await body()
}

private func withEnvironment(_ overrides: [String: String?], body: () throws -> Void) rethrows {
    let environment = ProcessInfo.processInfo.environment
    let previous = overrides.keys.map { ($0, environment[$0]) }
    defer { previous.forEach(setEnvironment) }
    overrides.forEach(setEnvironment)
    try body()
}

/// Resolves every symlink, including `/var` → `/private/var`, to match `pwd -P`.
private func realPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
}

private func setEnvironment(_ name: String, _ value: String?) {
    if let value {
        setenv(name, value, 1)
    } else {
        unsetenv(name)
    }
}

@Suite(.serialized) struct ClaudeCLITests {
    @Test func successReturnsTrimmedStdoutAndReceivesPromptOnStdin() async throws {
        let fake = try FakeClaude(script: #"cat > "$DIR/stdin"; printf '\n  polished text \n\n'"#)
        defer { fake.remove() }

        let output = try await fake.cli.run(
            prompt: "system\n\n---\n\nhello", model: "haiku", timeout: .seconds(10)
        ).text

        #expect(output == "polished text")
        #expect(try fake.contents(of: "stdin") == "system\n\n---\n\nhello")
    }

    @Test func passesExactHeadlessArguments() async throws {
        let fake = try FakeClaude(script: #"printf '%s\n' "$@" > "$DIR/args"; echo ok"#)
        defer { fake.remove() }

        _ = try await fake.cli.run(prompt: "p", model: "claude-sonnet-5-5", timeout: .seconds(10))

        let arguments = try fake.contents(of: "args").split(separator: "\n").map(String.init)
        #expect(
            arguments == [
                "--print", "--output-format", "text", "--model", "claude-sonnet-5-5",
                "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
                "--no-session-persistence",
            ])
    }

    @Test func runsInTemporaryDirectoryNotCallersDirectory() async throws {
        let fake = try FakeClaude(script: #"pwd -P > "$DIR/cwd"; echo ok"#)
        defer { fake.remove() }

        _ = try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))

        let cwd = try fake.contents(of: "cwd").trimmingCharacters(in: .newlines)
        #expect(cwd == realPath(FileManager.default.temporaryDirectory.path))
        #expect(cwd != realPath(FileManager.default.currentDirectoryPath))
    }

    @Test func stripsApiKeyAndSetsHeadlessEnvironment() async throws {
        let fake = try FakeClaude(script: #"env > "$DIR/env"; echo ok"#)
        defer { fake.remove() }

        try await withEnvironment(["ANTHROPIC_API_KEY": "sk-test-should-not-leak"]) {
            _ = try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))
        }

        let environment = try fake.recordedEnvironment()
        #expect(environment["ANTHROPIC_API_KEY"] == nil)
        #expect(environment["MAX_THINKING_TOKENS"] == "0")
        #expect(environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] == "1")
        let path = try #require(environment["PATH"])
        #expect(path.hasPrefix("\(fake.directory.path):"))
        #expect(path.contains("/opt/homebrew/bin"))
    }

    @Test func fillsInMissingUserAndHome() async throws {
        let fake = try FakeClaude(script: #"env > "$DIR/env"; echo ok"#)
        defer { fake.remove() }

        try await withEnvironment(["USER": nil, "HOME": nil]) {
            _ = try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))
        }

        let environment = try fake.recordedEnvironment()
        #expect(environment["USER"] == NSUserName())
        #expect(environment["HOME"] == NSHomeDirectory())
    }

    @Test func keepsUserAndHomeThatAreAlreadySet() async throws {
        let fake = try FakeClaude(script: #"env > "$DIR/env"; echo ok"#)
        defer { fake.remove() }

        try await withEnvironment(["USER": "someone-else", "HOME": "/tmp/elsewhere"]) {
            _ = try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))
        }

        let environment = try fake.recordedEnvironment()
        #expect(environment["USER"] == "someone-else")
        #expect(environment["HOME"] == "/tmp/elsewhere")
    }

    @Test func failureOnStdoutOnlyIsReported() async throws {
        let fake = try FakeClaude(script: "echo 'Not logged in · Please run /login'; exit 1")
        defer { fake.remove() }

        await #expect(throws: PolishError.cliFailed(stderr: "Not logged in · Please run /login")) {
            try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))
        }
    }

    @Test func stderrIsPreferredOverStdoutOnFailure() async throws {
        let fake = try FakeClaude(script: "echo partial; echo 'real error' >&2; exit 1")
        defer { fake.remove() }

        await #expect(throws: PolishError.cliFailed(stderr: "real error")) {
            try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))
        }
    }

    @Test func nonZeroExitIsRetriedOnceThenFailsWithStderr() async throws {
        let fake = try FakeClaude(script: "\(countInvocation); echo '  rate limited  ' >&2; exit 3")
        defer { fake.remove() }

        await #expect(throws: PolishError.cliFailed(stderr: "rate limited")) {
            try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))
        }
        #expect(try fake.invocationCount() == 2)
    }

    @Test func failureThenSuccessReturnsSecondOutput() async throws {
        let script = """
            \(countInvocation)
            if [ "$(wc -l < "$DIR/count")" -lt 2 ]; then echo boom >&2; exit 1; fi
            echo recovered
            """
        let fake = try FakeClaude(script: script)
        defer { fake.remove() }

        let output = try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10)).text

        #expect(output == "recovered")
        #expect(try fake.invocationCount() == 2)
    }

    @Test func timeoutTerminatesAndIsNotRetried() async throws {
        let fake = try FakeClaude(script: "\(countInvocation); sleep 5")
        defer { fake.remove() }
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: PolishError.timeout(seconds: 1)) {
            try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(1))
        }
        #expect(clock.now - start < .seconds(4))
        #expect(try fake.invocationCount() == 1)
    }

    @Test func timeoutEscalatesToKillWhenTermIsIgnored() async throws {
        let fake = try FakeClaude(script: "\(countInvocation); trap '' TERM; sleep 5")
        defer { fake.remove() }
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: PolishError.timeout(seconds: 1)) {
            try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(1))
        }
        #expect(clock.now - start < .seconds(5))
        #expect(try fake.invocationCount() == 1)
    }

    @Test func largeOutputAndInputDoNotDeadlock() async throws {
        let script =
            #"cat > "$DIR/stdin"; head -c 1048576 /dev/zero | tr '\0' 'a'; "#
            + #"head -c 262144 /dev/zero | tr '\0' 'e' >&2"#
        let fake = try FakeClaude(script: script)
        defer { fake.remove() }
        let prompt = String(repeating: "p", count: 200_000)

        let output = try await fake.cli.run(prompt: prompt, model: "haiku", timeout: .seconds(10))
            .text

        #expect(output.utf8.count == 1_048_576)
        #expect(try fake.contents(of: "stdin").utf8.count == 200_000)
    }

    @Test func childThatIgnoresStdinStillSucceeds() async throws {
        let fake = try FakeClaude(script: "echo early")
        defer { fake.remove() }
        let prompt = String(repeating: "p", count: 500_000)

        let output = try await fake.cli.run(prompt: prompt, model: "haiku", timeout: .seconds(10))
            .text

        #expect(output == "early")
    }

    @Test func missingBinaryThrowsNotFoundFromRunAndCheckAvailable() async throws {
        let fake = try FakeClaude(script: "echo ok", executable: false)
        defer { fake.remove() }

        await #expect(throws: PolishError.claudeNotFound) {
            try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))
        }
        await #expect(throws: PolishError.claudeNotFound) {
            try await fake.cli.checkAvailable()
        }
    }

    @Test func checkAvailableSucceedsWhenBinaryExists() async throws {
        let fake = try FakeClaude(script: "echo ok")
        defer { fake.remove() }

        try await fake.cli.checkAvailable()
    }

    @Test func foundBinaryIsCachedUntilItStopsBeingExecutable() async throws {
        let preferred = try FakeClaude(script: "echo preferred")
        let fallback = try FakeClaude(script: "echo fallback")
        defer {
            preferred.remove()
            fallback.remove()
        }
        try preferred.uninstall()
        let cli = ClaudeCLI(
            locator: ClaudeBinaryLocator(
                searchDirectories: [preferred.directory, fallback.directory],
                useLoginShell: false))

        #expect(
            try await cli.run(prompt: "p", model: "haiku", timeout: .seconds(10)).text == "fallback"
        )
        try preferred.install()
        #expect(
            try await cli.run(prompt: "p", model: "haiku", timeout: .seconds(10)).text == "fallback"
        )
        try fallback.uninstall()
        #expect(
            try await cli.run(prompt: "p", model: "haiku", timeout: .seconds(10)).text
                == "preferred")
    }

    @Test func cancellingTheTaskKillsTheProcess() async throws {
        try await expectStopsSleepingFake { task in task.cancel() }
    }

    @Test func terminateRunningProcessesKillsTheProcess() async throws {
        try await expectStopsSleepingFake { _ in ClaudeCLI.terminateRunningProcesses() }
    }

    private func expectStopsSleepingFake(
        _ stop: (Task<ClaudeReply, any Error>) -> Void
    ) async throws {
        let fake = try FakeClaude(script: #"echo $$ > "$DIR/pid"; exec sleep 10"#)
        defer { fake.remove() }
        let cli = fake.cli
        let task = Task { try await cli.run(prompt: "p", model: "haiku", timeout: .seconds(30)) }
        let pid = try await waitForPid(of: fake)
        let clock = ContinuousClock()
        let stoppedAt = clock.now

        stop(task)
        let result = await task.result

        #expect(clock.now - stoppedAt < .seconds(3))
        #expect(throws: PolishError.cliFailed(stderr: "Cancelled")) { try result.get() }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }

    private func waitForPid(of fake: FakeClaude) async throws -> pid_t {
        for _ in 0..<100 {
            let text = (try? fake.contents(of: "pid"))?.trimmingCharacters(in: .newlines)
            if let text, let pid = pid_t(text) {
                return pid
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("fake claude never started")
        throw CancellationError()
    }

    @Test func failureDetailIsCapped() async throws {
        let fake = try FakeClaude(script: "head -c 5000 /dev/zero | tr '\\0' 's' >&2; exit 1")
        defer { fake.remove() }

        do {
            _ = try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))
            Issue.record("expected cliFailed")
        } catch {
            guard case .cliFailed(let detail) = error else {
                Issue.record("expected cliFailed, got \(error)")
                return
            }
            #expect(detail.hasPrefix(String(repeating: "s", count: 500)))
            #expect(detail.count < 520)
        }
    }

    @Test func unlaunchableBinaryFailsWithLaunchError() async throws {
        let fake = try FakeClaude(contents: "#!/nonexistent/interpreter\necho never\n")
        defer { fake.remove() }

        do {
            _ = try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))
            Issue.record("expected cliFailed")
        } catch {
            guard case .cliFailed(let detail) = error else {
                Issue.record("expected cliFailed, got \(error)")
                return
            }
            #expect(detail.hasPrefix("Couldn't launch \(fake.binary.path)"))
        }
    }

    // The login shell inherits this process's environment, so ZDOTDIR points zsh at a
    // temporary .zprofile/.zshrc and PATH is reduced so the real claude isn't found.

    @Test func loginShellFindsBinaryOnZprofilePathAndUsesLastLine() throws {
        let fake = try FakeClaude(script: "echo ok")
        defer { fake.remove() }
        let zprofile = "export PATH=\"\(fake.directory.path):$PATH\"\necho 'welcome banner'\n"

        let found = try locateWithLoginShell(dotfiles: [".zprofile": zprofile])

        #expect(found?.path == fake.binary.path)
    }

    @Test(arguments: ["alias claude='echo hi'", "claude() { :; }"])
    func loginShellRejectsNonPathOutput(definition: String) throws {
        let fake = try FakeClaude(script: "echo ok")
        defer { fake.remove() }
        // A real binary is on PATH too; the alias/function shadows it in `command -v`.
        let zprofile = "export PATH=\"\(fake.directory.path):$PATH\"\n\(definition)\n"

        #expect(try locateWithLoginShell(dotfiles: [".zprofile": zprofile]) == nil)
    }

    @Test func loginShellIgnoresPathSetOnlyInZshrc() throws {
        let fake = try FakeClaude(script: "echo ok")
        defer { fake.remove() }
        let zshrc = "export PATH=\"\(fake.directory.path):$PATH\"\n"

        let found = try locateWithLoginShell(dotfiles: [".zshrc": zshrc])

        #expect(found?.path != fake.binary.path)
    }

    private func locateWithLoginShell(dotfiles: [String: String]) throws -> URL? {
        let zdotdir = FileManager.default.temporaryDirectory
            .appending(path: "ClaudeCLITests-zdotdir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: zdotdir) }
        for (name, contents) in dotfiles {
            try contents.write(to: zdotdir.appending(path: name), atomically: true, encoding: .utf8)
        }
        let locator = ClaudeBinaryLocator(searchDirectories: [], useLoginShell: true)
        var found: URL?
        withEnvironment(["ZDOTDIR": zdotdir.path, "PATH": "/usr/bin:/bin"]) {
            found = locator.locate()
        }
        return found
    }
}

@Suite struct ClaudeBinaryLocatorTests {
    @Test func picksFirstDirectoryInOrder() throws {
        let first = try FakeClaude(script: "echo first")
        let second = try FakeClaude(script: "echo second")
        defer {
            first.remove()
            second.remove()
        }

        let locator = ClaudeBinaryLocator(
            searchDirectories: [first.directory, second.directory], useLoginShell: false)

        #expect(locator.locate()?.standardizedFileURL == first.binary.standardizedFileURL)
    }

    @Test func skipsNonExecutableFiles() throws {
        let notExecutable = try FakeClaude(script: "echo no", executable: false)
        let executable = try FakeClaude(script: "echo yes")
        defer {
            notExecutable.remove()
            executable.remove()
        }

        let locator = ClaudeBinaryLocator(
            searchDirectories: [notExecutable.directory, executable.directory],
            useLoginShell: false)

        #expect(locator.locate()?.standardizedFileURL == executable.binary.standardizedFileURL)
    }

    @Test func skipsDirectoryNamedClaude() throws {
        let parent = FileManager.default.temporaryDirectory
            .appending(path: "ClaudeCLITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: parent.appending(path: "claude"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let locator = ClaudeBinaryLocator(searchDirectories: [parent], useLoginShell: false)

        #expect(locator.locate() == nil)
    }

    @Test func noCandidatesReturnsNil() {
        let locator = ClaudeBinaryLocator(searchDirectories: [], useLoginShell: false)

        #expect(locator.locate() == nil)
    }

    @Test func defaultSearchDirectoriesCoverUserAndHomebrewLocations() {
        let paths = ClaudeBinaryLocator.defaultSearchDirectories.map(\.path)
        let home = NSHomeDirectory()

        #expect(paths == ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"])
    }
}
