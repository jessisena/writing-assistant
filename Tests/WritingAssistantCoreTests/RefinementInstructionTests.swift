import Foundation
import Testing
import WritingAssistantCore

@Suite struct RefinementInstructionTests {
    private let limit = RefinementInstruction.maxCustomLength

    @Test func presetIsReturnedUnchanged() throws {
        #expect(try RefinementInstruction.preset(.shorter).validated() == .preset(.shorter))
    }

    @Test func customIsTrimmed() throws {
        let instruction = RefinementInstruction.custom("  mention the deadline is Friday \n")
        #expect(try instruction.validated() == .custom("mention the deadline is Friday"))
    }

    @Test(arguments: [
        "", " \n\t ", "{{CHANNEL_GUIDELINES}}", " {{ALWAYS{{REFINEMENT_INSTRUCTION}}_RULES}} ",
    ])
    func blankCustomIsRejected(text: String) {
        #expect(throws: PolishError.emptyInstruction) {
            try RefinementInstruction.custom(text).validated()
        }
    }

    @Test func customAtTheLimitIsAccepted() throws {
        let text = String(repeating: "é", count: limit)
        #expect(try RefinementInstruction.custom(" \(text) ").validated() == .custom(text))
    }

    @Test func customOverTheLimitIsRejected() {
        let text = String(repeating: "a", count: limit + 1)
        #expect(throws: PolishError.instructionTooLong(limit: limit)) {
            try RefinementInstruction.custom(text).validated()
        }
    }

    @Test func placeholdersAreRemovedFromCustom() throws {
        let text =
            "less emoji \(PromptFile.channelPlaceholder){{ALWAYS{{LEARNING_SUMMARY}}_RULES}}"
            + " \(PromptFile.instructionPlaceholder)"
        #expect(try RefinementInstruction.custom(text).validated() == .custom("less emoji"))
    }

    @Test func tooLongMessageNamesTheLimit() {
        let message = PolishError.instructionTooLong(limit: limit).errorDescription
        #expect(message?.contains("500") == true)
    }
}

@Suite final class CustomRefinementPromptTests {
    let root: URL
    let store: PromptStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(
                path: "CustomRefinementTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = PromptStore(directoryURL: root.appending(path: "prompts"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func trimmedBundled(_ file: PromptFile) throws -> String {
        let url = PromptStore.bundledDefaultsURL.appending(path: file.relativePath)
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func customTextFillsTheInstructionSection() throws {
        try store.seedMissingDefaults()

        let prompt = try store.assembleRefinement(
            .custom("mention the deadline is Friday"), for: .email)

        #expect(prompt.contains(try trimmedBundled(.always)))
        #expect(prompt.contains(try trimmedBundled(.channel(.email))))
        #expect(prompt.contains("## Instruction\n\nmention the deadline is Friday\n"))
        #expect(!prompt.contains("{{"))
        for refinement in Refinement.allCases {
            #expect(!prompt.contains(try trimmedBundled(.refinement(refinement))))
        }
    }

    @Test func placeholdersInCustomTextPullNothingIn() throws {
        try store.seedMissingDefaults()
        let guidelines = try trimmedBundled(.channel(.slack))
        let text = "\(PromptFile.channelPlaceholder) less emoji \(PromptFile.alwaysPlaceholder)"

        let prompt = try store.assembleRefinement(.custom(text), for: .slack)

        #expect(prompt.components(separatedBy: guidelines).count == 2)
        #expect(prompt.contains("## Instruction\n\nless emoji\n"))
        #expect(!prompt.contains("{{"))
    }

    @Test func customDoesNotReadTheRefinementFiles() throws {
        try store.seedMissingDefaults()
        for refinement in Refinement.allCases {
            try FileManager.default.removeItem(at: store.fileURL(.refinement(refinement)))
        }

        let prompt = try store.assembleRefinement(.custom("less emoji"), for: .slack)

        #expect(prompt.contains("less emoji"))
    }
}
