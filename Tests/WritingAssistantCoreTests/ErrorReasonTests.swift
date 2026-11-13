import Testing

@testable import WritingAssistantCore

@Suite struct ErrorReasonTests {
    @Test(arguments: [
        HistoryStoreError.readFailed(path: "/h.json", reason: "Permission denied."),
        HistoryStoreError.writeFailed(path: "/h.json", reason: "Permission denied."),
    ])
    func historyMessagesHaveNoDoublePeriod(error: HistoryStoreError) throws {
        let message = try #require(error.errorDescription)
        #expect(!message.contains(".."))
        #expect(message.contains("Permission denied. Check"))
    }

    @Test func learningLogMessageHasNoDoublePeriod() throws {
        let error = LearningLogError(path: "/log.md", reason: "Disk full.")
        let message = try #require(error.errorDescription)
        #expect(!message.contains(".."))
        #expect(message.contains("Disk full. Check"))
    }

    @Test func notLoggedInMessageGivesTheReloginCommand() throws {
        let message = try #require(PolishError.notLoggedIn(detail: "expired").errorDescription)
        #expect(message.contains("Run `claude auth login` in Terminal"))
    }

    @Test(arguments: [
        PolishError.cliFailed(stderr: "boom"),
        PolishError.notLoggedIn(detail: "expired"),
        PolishError.badFormat(detail: "not JSON"),
    ])
    func claudeFailuresPointToTheLogs(error: PolishError) throws {
        let message = try #require(error.errorDescription)
        #expect(message.contains("subsystem == \"local.writing-assistant\""))
        #expect(message.contains("Console.app"))
    }

    @Test func cliFailureShowsTheDetailWithoutDoublePeriod() throws {
        let message = try #require(
            PolishError.cliFailed(stderr: "Credit balance too low.").errorDescription)
        #expect(message.hasPrefix("Claude returned an error: Credit balance too low. Full"))
    }

    @Test func cliFailureWithoutDetailHasNoEmptyColon() throws {
        let message = try #require(PolishError.cliFailed(stderr: "").errorDescription)
        #expect(message.hasPrefix("Claude returned an error. Full"))
    }

    @Test func reasonWithoutPeriodIsKept() {
        #expect("No such file".withoutTrailingPeriod == "No such file")
        #expect("".withoutTrailingPeriod == "")
    }
}
