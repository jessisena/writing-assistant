import Testing
import WritingAssistantCore

@Suite struct ContractsTests {
    @Test func channelsMatchPromptFileNames() {
        #expect(
            Channel.allCases.map(\.rawValue) == [
                "slack", "slack_informal", "talking_points", "formal", "ai_prompt", "other",
            ])
    }

    @Test func promptFilesListGlobalFirstThenEveryChannel() {
        #expect(PromptFile.allCases.first == .global)
        #expect(PromptFile.allCases.count == Channel.allCases.count + 1)
        #expect(PromptFile.channel(.slackInformal).relativePath == "channels/slack_informal.txt")
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
