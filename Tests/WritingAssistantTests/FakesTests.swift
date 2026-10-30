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
        #expect(try store.assemble(for: .slack, learningSummary: true) == "Rules\nslack guidelines")
    }

    @Test func fakePromptStoreAssemblesTheRefinePrompt() throws {
        let store = FakePromptStore()
        #expect(
            try store.assembleRefinement(.preset(.shorter), for: .slack)
                == "Refine\nshorter instruction")
    }
}
