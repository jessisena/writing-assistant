import AppKit
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelRefineTests {
    private static let refined = PolishResult(
        polishedText: "Thanks, **will do** today.",
        learningSummary: nil,
        detectedLanguage: "Spanish",
        wasTranslated: true,
        modelUsed: ModelRouting.haikuModel
    )

    private func makeModel(_ polisher: any Polishing) -> AppModel {
        AppModel.testing(polisher: polisher)
    }

    private func markdown(_ text: NSAttributedString) -> String {
        RichText.markdown(from: RichTextBridge.attributedString(from: text))
    }

    private func polishedModel(_ polisher: FakePolisher) async -> AppModel {
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "I will to review the doc")
        await model.process()
        return model
    }

    private func waitUntil(_ polisher: GatedPolisher, hasCalls count: Int) async {
        while polisher.waitingCount < count { await Task.yield() }
    }

    /// A model showing `PolishResult.sample`, whose polisher waits for each later call.
    private func gatedPolishedModel() async -> (AppModel, GatedPolisher) {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)
        polisher.resume(0, with: .success(.sample))
        await model.requestTask?.value
        return (model, polisher)
    }

    @Test func editedOutputIsSentAsMarkdownWithRefinementAndChannel() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        model.channel = .slack
        model.output = AppModel.editorText(fromMarkdown: "  My **edited** *text* 🙂\n- one  \n")

        model.refine(.shorter)
        await model.requestTask?.value

        #expect(polisher.refineCalls.count == 1)
        #expect(polisher.refineCalls.first?.text == "My **edited** *text* 🙂\n- one")
        #expect(polisher.refineCalls.first?.channel == .slack)
        #expect(polisher.refineCalls.first?.refinement == .shorter)
    }

    @Test func refinedTextReplacesOutputAndKeepsSummaryAndLanguage() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        polisher.outcome = .success(Self.refined)

        model.refine(.moreCasual)
        await model.requestTask?.value

        #expect(markdown(model.output) == Self.refined.polishedText)
        #expect(model.result == .sample)
        #expect(model.result?.learningSummary == PolishResult.sample.learningSummary)
        #expect(model.result?.detectedLanguage == "English")
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
    }

    @Test func failureShowsBannerAndKeepsOutput() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        let before = model.output
        polisher.outcome = .failure(.timeout(seconds: 120))

        model.refine(.moreFormal)
        await model.requestTask?.value

        #expect(model.errorMessage == PolishError.timeout(seconds: 120).errorDescription)
        #expect(model.output.isEqual(to: before))
        #expect(model.result == .sample)
        #expect(!model.isLoading)
    }

    @Test func cancelLeavesOutputUnchanged() async {
        let (model, polisher) = await gatedPolishedModel()
        let before = model.output

        model.refine(.shorter)
        await waitUntil(polisher, hasCalls: 2)
        #expect(model.isLoading)
        model.cancel()
        polisher.resume(1, with: .success(Self.refined))
        await model.requestTask?.value

        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
        #expect(model.output.isEqual(to: before))
        #expect(model.result == .sample)
    }

    @Test func staleRefinementIsIgnoredAfterANewerRequest() async {
        let (model, polisher) = await gatedPolishedModel()
        model.refine(.shorter)
        await waitUntil(polisher, hasCalls: 2)
        let stale = model.requestTask
        model.cancel()

        model.refine(.moreFormal)
        await waitUntil(polisher, hasCalls: 3)
        let newerText = PolishResult(
            polishedText: "Newer refinement.", learningSummary: nil, detectedLanguage: "English",
            wasTranslated: false, modelUsed: ModelRouting.haikuModel)
        polisher.resume(2, with: .success(newerText))
        await model.requestTask?.value
        polisher.resume(1, with: .success(Self.refined))
        await stale?.value

        #expect(model.output.string == "Newer refinement.")
        #expect(!model.isLoading)
    }

    @Test func refineWhileLoadingIsIgnored() async {
        let (model, polisher) = await gatedPolishedModel()
        model.refine(.shorter)
        await waitUntil(polisher, hasCalls: 2)

        model.refine(.moreCasual)
        model.startProcessing()

        #expect(polisher.waitingCount == 2)
        #expect(!model.canRefine)
        polisher.resume(1, with: .success(Self.refined))
        await model.requestTask?.value
        #expect(model.canRefine)
    }

    @Test func blankOutputIsNotSent() async {
        let polisher = FakePolisher()
        let model = await polishedModel(polisher)
        model.output = NSAttributedString(string: " \n\t ")

        #expect(!model.canRefine)
        model.refine(.shorter)

        #expect(polisher.refineCalls.isEmpty)
        #expect(!model.isLoading)
    }

    @Test func cannotRefineWithoutAResult() {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.output = NSAttributedString(string: "Some text")

        #expect(!model.canRefine)
        model.refine(.shorter)

        #expect(polisher.refineCalls.isEmpty)
    }
}
