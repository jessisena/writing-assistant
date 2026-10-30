import AppKit
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelCustomRefineTests {
    private static let refined = PolishResult(
        polishedText: "Thanks, the deadline is **Friday**.",
        learningSummary: nil,
        detectedLanguage: "English",
        wasTranslated: false,
        modelUsed: ModelRouting.haikuModel
    )

    private func markdown(_ text: NSAttributedString) -> String {
        RichText.markdown(from: RichTextBridge.attributedString(from: text))
    }

    private func polishedModel(_ polisher: FakePolisher) async -> AppModel {
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "I will to review the doc")
        await model.process()
        return model
    }

    private func waitUntil(_ polisher: GatedPolisher, hasCalls count: Int) async {
        while polisher.waitingCount < count { await Task.yield() }
    }

    private func gatedPolishedModel() async -> (AppModel, GatedPolisher) {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
        return (model, polisher)
    }

    @Test func editedOutputIsSentWithTheTrimmedInstructionAndTheEntrysChannel() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        model.channel = .slack
        model.output = AppModel.editorText(fromMarkdown: "My **edited** text")
        model.customInstruction = "  mention the deadline is Friday \n"

        model.refineWithCustomInstruction()
        await model.requests.task?.value

        #expect(polisher.refineCalls.count == 1)
        #expect(polisher.refineCalls.first?.text == "My **edited** text")
        #expect(polisher.refineCalls.first?.channel == .formal)
        #expect(polisher.refineCalls.first?.refinement == .custom("mention the deadline is Friday"))
    }

    @Test func successReplacesOutputKeepsTheSummaryAndClearsTheField() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        polisher.outcome = .success(Self.refined)
        model.customInstruction = "less emoji"

        model.refineWithCustomInstruction()
        await model.requests.task?.value

        #expect(markdown(model.output) == Self.refined.polishedText)
        #expect(model.result == .sample)
        #expect(model.customInstruction.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.history.first?.outputMarkdown == Self.refined.polishedText)
    }

    @Test func failureShowsBannerAndKeepsTheInstruction() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        let before = model.output
        polisher.outcome = .failure(.timeout(seconds: 120))
        model.customInstruction = "less emoji"

        model.refineWithCustomInstruction()
        await model.requests.task?.value

        #expect(model.errorMessage == PolishError.timeout(seconds: 120).errorDescription)
        #expect(model.customInstruction == "less emoji")
        #expect(model.output.isEqual(to: before))
    }

    @Test(arguments: ["", "   ", " \n\t "])
    func blankInstructionDoesNothing(text: String) async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        model.customInstruction = text

        model.refineWithCustomInstruction()

        #expect(polisher.refineCalls.isEmpty)
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
        #expect(model.customInstruction == text)
    }

    @Test func tooLongInstructionShowsTheLimitAndIsNotSent() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        let limit = RefinementInstruction.maxCustomLength
        let text = String(repeating: "a", count: limit + 1)
        model.customInstruction = text

        model.refineWithCustomInstruction()

        #expect(polisher.refineCalls.isEmpty)
        #expect(!model.isLoading)
        #expect(
            model.errorMessage == PolishError.instructionTooLong(limit: limit).errorDescription)
        #expect(model.customInstruction == text)
    }

    @Test func instructionAtTheLimitIsSent() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        let text = String(repeating: "a", count: RefinementInstruction.maxCustomLength)
        model.customInstruction = text

        model.refineWithCustomInstruction()
        await model.requests.task?.value

        #expect(polisher.refineCalls.first?.refinement == .custom(text))
    }

    @Test func placeholderTokensAreStrippedBeforeSending() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        model.customInstruction = "less emoji \(PromptFile.channelPlaceholder)"

        model.refineWithCustomInstruction()
        await model.requests.task?.value

        #expect(polisher.refineCalls.first?.refinement == .custom("less emoji"))
    }

    @Test func runningRefinementIsCustomAndCancelKeepsTheInstruction() async {
        let (model, polisher) = await gatedPolishedModel()
        let before = model.output
        model.customInstruction = "less emoji"

        model.refineWithCustomInstruction()
        await waitUntil(polisher, hasCalls: 2)
        #expect(model.runningRefinement == .custom("less emoji"))
        #expect(!model.canRefine)
        model.cancel()
        polisher.resume(1, with: .success(Self.refined))
        await model.requests.task?.value

        #expect(model.runningRefinement == nil)
        #expect(model.errorMessage == nil)
        #expect(model.output.isEqual(to: before))
        #expect(model.customInstruction == "less emoji")
    }

    @Test func cannotRefineWithoutAResult() {
        let polisher = FakePolisher()
        let model = AppModel.testing(polisher: polisher)
        model.output = NSAttributedString(string: "Some text")
        model.customInstruction = "less emoji"

        model.refineWithCustomInstruction()

        #expect(polisher.refineCalls.isEmpty)
        #expect(model.customInstruction == "less emoji")
    }
}
