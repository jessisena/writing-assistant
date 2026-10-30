import Testing
import WritingAssistantCore

@testable import WritingAssistant

@Suite struct FakesTests {
    @Test func fakePromptStoreAppliesRealValidation() {
        let store = FakePromptStore()
        #expect(throws: PromptValidationError.missingPlaceholder(PromptFile.channelPlaceholder)) {
            try store.write("no placeholder", to: .global)
        }
    }

    @Test func fakePromptStoreAssemblesChannelIntoGlobal() throws {
        let store = FakePromptStore()
        let options = PolishOptions(
            mode: .work, outputLanguage: .english, includesLearningSummary: true)
        #expect(try store.assemble(for: .slack, options: options) == "Rules\nslack guidelines")
    }

    @Test func fakePromptStoreAssemblesTheRefinePrompt() throws {
        let store = FakePromptStore()
        #expect(
            try store.assembleRefinement(.shorter, for: .slack) == "Refine\nshorter instruction")
    }
}
