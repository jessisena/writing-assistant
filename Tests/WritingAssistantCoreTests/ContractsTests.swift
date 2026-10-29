import Testing
import WritingAssistantCore

@Suite struct ContractsTests {
    @Test func channelsMatchPromptFileNames() {
        #expect(
            Channel.allCases.map(\.rawValue) == [
                "slack", "slack_informal", "talking_points", "formal", "ai_prompt", "other",
            ])
    }

    @Test func channelsHaveShortNamesForChips() {
        #expect(
            Channel.allCases.map(\.shortName) == [
                "Slack", "Casual Slack", "Talking points", "Formal doc", "AI prompt", "General",
            ])
    }

    @Test func promptFilesListGlobalThenChannelsThenRefinements() {
        let expected: [PromptFile] =
            [.global] + Channel.allCases.map { .channel($0) }
            + Refinement.allCases.map { .refinement($0) }
        #expect(PromptFile.allCases == expected)
        #expect(PromptFile.channel(.slackInformal).relativePath == "channels/slack_informal.txt")
    }

    @Test func refinementsMatchPromptFileNames() {
        #expect(
            Refinement.allCases.map(\.rawValue) == [
                "shorter", "more_casual", "more_formal", "more_diplomatic", "more_assertive",
            ])
        #expect(Refinement.allCases.map(\.id) == Refinement.allCases.map(\.rawValue))
        #expect(
            Refinement.allCases.map { PromptFile.refinement($0).relativePath } == [
                "refinements/shorter.txt", "refinements/more_casual.txt",
                "refinements/more_formal.txt", "refinements/more_diplomatic.txt",
                "refinements/more_assertive.txt",
            ])
    }

    @Test func refinementDisplayNamesAreUsedByPromptFiles() {
        #expect(
            Refinement.allCases.map(\.displayName) == [
                "Shorter", "More casual", "More formal", "More diplomatic", "More assertive",
            ])
        #expect(PromptFile.refinement(.moreFormal).displayName == "More formal")
    }

    @Test func promptFileIdsAreUnique() {
        #expect(Set(PromptFile.allCases.map(\.id)).count == PromptFile.allCases.count)
    }

    @Test(arguments: ["", "  \n\t"])
    func blankRefinementPromptIsRejected(text: String) {
        #expect(throws: PromptValidationError.empty) {
            try PromptFile.refinement(.shorter).validate(text)
        }
    }

    @Test func refinementPromptDoesNotNeedPlaceholder() throws {
        try PromptFile.refinement(.moreCasual).validate("Make it friendlier.")
    }

    @Test(arguments: ["", "   \n\t"])
    func blankPromptIsRejected(text: String) {
        #expect(throws: PromptValidationError.empty) {
            try PromptFile.channel(.slack).validate(text)
        }
    }

    @Test func globalPromptWithoutPlaceholderIsRejected() {
        #expect(throws: PromptValidationError.missingPlaceholder) {
            try PromptFile.global.validate("Rules without the placeholder")
        }
    }

    @Test func channelPromptDoesNotNeedPlaceholder() throws {
        try PromptFile.channel(.formal).validate("Use headers.")
        try PromptFile.global.validate("Rules\n\(PromptFile.channelPlaceholder)")
    }

    @Test func timeoutMessageMatchesThePythonServer() {
        #expect(
            PolishError.timeout(seconds: 120).errorDescription
                == "Claude took longer than 120 seconds. Please try again.")
    }
}
