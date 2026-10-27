import Testing
import WritingAssistantCore

@testable import WritingAssistant

@Suite struct FakesTests {
    @Test func fakePromptStoreAppliesRealValidation() {
        let store = FakePromptStore()
        #expect(throws: PromptValidationError.missingPlaceholder) {
            try store.write("no placeholder", to: .global)
        }
    }

    @Test func fakePromptStoreAssemblesChannelIntoGlobal() throws {
        let store = FakePromptStore()
        #expect(try store.assemble(for: .slack) == "Rules\nslack guidelines")
    }
}
