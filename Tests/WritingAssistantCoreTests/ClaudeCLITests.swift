import Foundation
import Testing
import WritingAssistantCore

/// A temporary directory holding a fake `claude` shell script. The script can write files next
/// to itself (`$DIR`) so tests can inspect what the real process received.
private struct FakeClaude {
    let directory: URL

    init(script: String, executable: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "ClaudeCLITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appending(path: "claude")
        let body = "#!/bin/sh\nDIR=\"$(dirname \"$0\")\"\n\(script)\n"
        try body.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: binary.path)
    }

    var binary: URL { directory.appending(path: "claude") }

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

private let countInvocation = #"echo x >> "$DIR/count""#

@Suite(.serialized) struct ClaudeCLITests {
    @Test func successReturnsTrimmedStdoutAndReceivesPromptOnStdin() async throws {
        let fake = try FakeClaude(script: #"cat > "$DIR/stdin"; printf '\n  polished text \n\n'"#)
        defer { fake.remove() }

        let output = try await fake.cli.run(
            prompt: "system\n\n---\n\nhello", model: "haiku", timeout: .seconds(10))

        #expect(output == "polished text")
        #expect(try fake.contents(of: "stdin") == "system\n\n---\n\nhello")
    }

    @Test func passesExactHeadlessArguments() async throws {
        let fake = try FakeClaude(script: #"printf '%s\n' "$@" > "$DIR/args"; echo ok"#)
        defer { fake.remove() }

        _ = try await fake.cli.run(prompt: "p", model: "claude-sonnet-4-6", timeout: .seconds(10))

        let arguments = try fake.contents(of: "args").split(separator: "\n").map(String.init)
        #expect(
            arguments == [
                "--print", "--output-format", "text", "--model", "claude-sonnet-4-6",
                "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
                "--no-session-persistence",
            ])
    }

    @Test func stripsApiKeyAndSetsHeadlessEnvironment() async throws {
        let fake = try FakeClaude(script: #"env > "$DIR/env"; echo ok"#)
        defer { fake.remove() }
        let previousKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        setenv("ANTHROPIC_API_KEY", "sk-test-should-not-leak", 1)
        defer {
            if let previousKey {
                setenv("ANTHROPIC_API_KEY", previousKey, 1)
            } else {
                unsetenv("ANTHROPIC_API_KEY")
            }
        }

        _ = try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))

        let lines = try fake.contents(of: "env").split(separator: "\n").map(String.init)
        #expect(!lines.contains { $0.hasPrefix("ANTHROPIC_API_KEY=") })
        #expect(lines.contains("MAX_THINKING_TOKENS=0"))
        #expect(lines.contains("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"))
        let path = try #require(lines.first { $0.hasPrefix("PATH=") })
        #expect(path.hasPrefix("PATH=\(fake.directory.path):"))
        #expect(path.contains("/opt/homebrew/bin"))
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

        let output = try await fake.cli.run(prompt: "p", model: "haiku", timeout: .seconds(10))

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

        #expect(output.utf8.count == 1_048_576)
        #expect(try fake.contents(of: "stdin").utf8.count == 200_000)
    }

    @Test func childThatIgnoresStdinStillSucceeds() async throws {
        let fake = try FakeClaude(script: "echo early")
        defer { fake.remove() }
        let prompt = String(repeating: "p", count: 500_000)

        let output = try await fake.cli.run(prompt: prompt, model: "haiku", timeout: .seconds(10))

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
