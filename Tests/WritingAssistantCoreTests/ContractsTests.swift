import Testing
import WritingAssistantCore

@Suite struct ContractsTests {
    @Test func channelsMatchPromptFileNames() {
        #expect(
            Channel.allCases.map(\.rawValue) == [
                "slack", "slack_informal", "talking_points", "formal", "ai_prompt", "email",
                "personal_message", "proofread", "other",
            ])
    }

    @Test func channelsHaveShortNamesForChips() {
        #expect(
            Channel.allCases.map(\.shortName) == [
                "Slack", "Casual Slack", "Talking points", "Formal doc", "AI prompt", "Email",
                "Personal", "Proofread", "General",
            ])
    }

    @Test func promptFilesListTopLevelFilesThenChannelsThenRefinements() {
        let expected: [PromptFile] =
            [.global, .always, .learningSummary, .refine] + Channel.allCases.map { .channel($0) }
            + Refinement.allCases.map { .refinement($0) }
        #expect(PromptFile.allCases == expected)
        #expect(
            [PromptFile.global, .always, .learningSummary, .refine].map(\.relativePath) == [
                "polish.txt", "always.txt", "learning_summary.txt", "refine.txt",
            ])
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
        let error = PromptValidationError.missingPlaceholder(PromptFile.channelPlaceholder)
        #expect(throws: error) {
            try PromptFile.global.validate("Rules without the placeholder")
        }
        #expect(error.errorDescription?.contains("channel guidelines") == true)
    }

    @Test func refinePromptWithoutInstructionPlaceholderIsRejected() {
        let error = PromptValidationError.missingPlaceholder(PromptFile.instructionPlaceholder)
        #expect(throws: error) {
            try PromptFile.refine.validate("Refine \(PromptFile.channelPlaceholder)")
        }
        #expect(error.errorDescription?.contains("refinement instruction") == true)
    }

    @Test func onlyTheTemplatesNeedTheirPlaceholder() throws {
        try PromptFile.channel(.formal).validate("Use headers.")
        try PromptFile.always.validate("Be clear.")
        try PromptFile.learningSummary.validate("Explain the changes.")
        try PromptFile.global.validate("Rules\n\(PromptFile.channelPlaceholder)")
        try PromptFile.refine.validate("Refine\n\(PromptFile.instructionPlaceholder)")
    }

    @Test func timeoutMessageMatchesThePythonServer() {
        #expect(
            PolishError.timeout(seconds: 120).errorDescription
                == "Claude took longer than 120 seconds. Please try again.")
    }

    @Test func outdatedCLIMessageSaysHowToUpdate() throws {
        let message = try #require(
            PolishError.cliOutdated(detail: "error: unknown option '--tools'").errorDescription)
        #expect(message.contains("too old"))
        #expect(message.contains("`claude update`"))
    }
}
