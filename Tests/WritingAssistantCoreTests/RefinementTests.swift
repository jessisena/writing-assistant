import Foundation
import Testing
import WritingAssistantCore

@Suite final class RefinementPromptStoreTests {
    let root: URL
    let store: PromptStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "RefinementTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = PromptStore(directoryURL: root.appending(path: "prompts"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func bundledText(_ refinement: Refinement) throws -> String {
        let url = PromptStore.bundledDefaultsURL
            .appending(path: PromptFile.refinement(refinement).relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test(arguments: Refinement.allCases)
    func bundledDefaultIsAValidPromptWithoutEmDashes(refinement: Refinement) throws {
        let text = try bundledText(refinement)
        try PromptFile.refinement(refinement).validate(text)
        #expect(!text.contains("\u{2014}"))
    }

    @Test(arguments: Refinement.allCases)
    func seedingCreatesTheRefinementFile(refinement: Refinement) throws {
        try store.seedMissingDefaults()

        #expect(try store.read(.refinement(refinement)) == bundledText(refinement))
    }

    @Test func restoreDefaultResetsAnEditedRefinement() throws {
        try store.seedMissingDefaults()
        try store.write("Cut it in half.", to: .refinement(.shorter))
        #expect(try store.read(.refinement(.shorter)) == "Cut it in half.")

        try store.restoreDefault(.refinement(.shorter))

        #expect(try store.read(.refinement(.shorter)) == bundledText(.shorter))
    }

    @Test func blankRefinementIsNotWritten() throws {
        try store.seedMissingDefaults()
        #expect(throws: PromptValidationError.empty) {
            try self.store.write(" \n", to: .refinement(.moreFormal))
        }
        #expect(try store.read(.refinement(.moreFormal)) == bundledText(.moreFormal))
    }

    @Test func refinementEndToEndUsesTheStoredInstruction() async throws {
        try store.seedMissingDefaults()
        try store.write("Use at most ten words.", to: .refinement(.shorter))
        let runner = RecordingRunner()
        let service = PolishService(runner: runner, prompts: store)

        let refined = try await service.refine(
            text: "Hello there", channel: .slack, refinement: .preset(.shorter))

        #expect(refined == "Hi")
        let prompt = try #require(await runner.prompts.first)
        #expect(prompt.contains("## Instruction\n\nUse at most ten words."))
        #expect(await runner.inputs.first == "<draft>\nHello there\n</draft>")
        let guidelines = try store.read(.channel(.slack))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(prompt.contains(guidelines))
    }
}

private actor RecordingRunner: ClaudeRunning {
    /// The system prompt of each call.
    private(set) var prompts: [String] = []
    /// The stdin input of each call.
    private(set) var inputs: [String] = []

    func run(
        systemPrompt: String, input: String, model: String, timeout: Duration,
        onText: @escaping @Sendable (String) -> Void
    ) async throws(PolishError) -> ClaudeReply {
        prompts.append(systemPrompt)
        inputs.append(input)
        return ClaudeReply(
            text: #"{"polished_text": "Hi", "was_translated": false, "learning_summary": null}"#,
            usage: nil)
    }

    func checkAvailable() async throws(PolishError) {}
}
