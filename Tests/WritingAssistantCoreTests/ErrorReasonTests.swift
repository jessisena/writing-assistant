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

    @Test func reasonWithoutPeriodIsKept() {
        #expect("No such file".withoutTrailingPeriod == "No such file")
        #expect("".withoutTrailingPeriod == "")
    }
}
