import AppKit
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelTests {
    private func makeModel(_ polisher: FakePolisher) -> AppModel {
        AppModel.testing(polisher: polisher)
    }

    private func richText(_ markdown: String) -> NSAttributedString {
        AppModel.editorText(fromMarkdown: markdown)
    }

    private func markdown(_ text: NSAttributedString) -> String {
        RichText.markdown(from: RichTextBridge.attributedString(from: text))
    }

    @Test func defaultChannelIsFormal() {
        #expect(makeModel(FakePolisher()).channel == .formal)
    }

    @Test(arguments: ["", "   ", "\n\t  \n"])
    func blankInputShowsEmptyMessageWithoutCallingPolisher(input: String) async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: input)

        await model.process()

        #expect(model.errorMessage == PolishError.emptyInput.errorDescription)
        #expect(polisher.calls.isEmpty)
        #expect(model.result == nil)
        #expect(!model.isLoading)
    }

    @Test func successStoresResultAndClearsEarlierError() async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        await model.process()
        #expect(model.errorMessage != nil)

        model.input = NSAttributedString(string: "I will to review the doc")
        await model.process()

        #expect(model.result == .sample)
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
    }

    @Test(arguments: [PolishError.timeout(seconds: 120), .claudeNotFound])
    func failureClearsEarlierResultAndShowsMessage(error: PolishError) async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")
        await model.process()
        #expect(model.result != nil)

        polisher.outcome = .failure(error)
        await model.process()

        #expect(model.result == nil)
        #expect(model.errorMessage == error.errorDescription)
        #expect(!model.isLoading)
    }

    @Test func trimmedTextAndSelectedChannelReachPolisher() async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "  \n hola equipo \n ")
        model.channel = .slackInformal

        await model.process()

        #expect(polisher.calls.count == 1)
        #expect(polisher.calls.first?.text == "hola equipo")
        #expect(polisher.calls.first?.channel == .slackInformal)
    }

    @Test func secondProcessWhileLoadingIsIgnored() async {
        let polisher = FakePolisher(delay: .milliseconds(200))
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")

        let first = Task { await model.process() }
        while !model.isLoading { await Task.yield() }
        #expect(model.result == nil)

        await model.process()
        #expect(model.isLoading)
        await first.value

        #expect(polisher.calls.count == 1)
        #expect(!model.isLoading)
        #expect(model.result == .sample)
    }

    @Test func readinessFailureShowsBanner() async {
        let model = makeModel(FakePolisher(readiness: .claudeNotFound))

        await model.checkReadiness()

        #expect(model.errorMessage == PolishError.claudeNotFound.errorDescription)
    }

    @Test func readinessSuccessLeavesBannerHidden() async {
        let model = makeModel(FakePolisher())

        await model.checkReadiness()

        #expect(model.errorMessage == nil)
    }

    @Test func startupErrorShowsBanner() {
        let model = makeModel(FakePolisher())

        model.showStartupError(PolishError.promptUnavailable(detail: "disk full"))

        #expect(
            model.errorMessage
                == PolishError.promptUnavailable(detail: "disk full").errorDescription)
    }

    @Test func startupErrorSurvivesSuccessfulReadinessCheck() async {
        let startup = PolishError.promptUnavailable(detail: "disk full")
        let model = makeModel(FakePolisher())
        model.showStartupError(startup)

        await model.checkReadiness()

        #expect(model.errorMessage == startup.errorDescription)
    }

    @Test func startupErrorAndReadinessFailureAreBothShown() async {
        let startup = PolishError.promptUnavailable(detail: "disk full")
        let model = makeModel(FakePolisher(readiness: .claudeNotFound))
        model.showStartupError(startup)

        await model.checkReadiness()

        let expected = [startup, .claudeNotFound].compactMap(\.errorDescription)
        #expect(model.errorMessage == expected.joined(separator: "\n"))
    }

    @Test func copyWritesTextAndResetsAfterDelay() async {
        var copied: [ClipboardContent] = []
        var copiedDuringDelay: Bool?
        var waited: [Duration] = []
        var model: AppModel?
        model = AppModel.testing(
            polisher: FakePolisher(),
            writeToPasteboard: { copied.append($0) },
            sleep: { duration in
                waited.append(duration)
                copiedDuringDelay = model?.copied
            }
        )
        guard let model else { return }
        model.input = NSAttributedString(string: "Hello")
        await model.process()

        await model.copyResult()

        let expected = RichText.attributedString(fromMarkdown: PolishResult.sample.polishedText)
        #expect(
            copied == [
                ClipboardContent(
                    html: RichText.html(from: expected),
                    plain: RichText.clipboardText(from: expected))
            ])
        #expect(copiedDuringDelay == true)
        #expect(waited == [.seconds(2)])
        #expect(!model.copied)
    }

    @Test func overlappingCopiesKeepCopiedUntilTheLastDelayEnds() async {
        var pending: [CheckedContinuation<Void, Never>] = []
        let model = AppModel.testing(
            polisher: FakePolisher(),
            writeToPasteboard: { _ in },
            sleep: { _ in await withCheckedContinuation { pending.append($0) } }
        )
        model.input = NSAttributedString(string: "Hello")
        await model.process()

        let first = Task { await model.copyResult() }
        while pending.count < 1 { await Task.yield() }
        let second = Task { await model.copyResult() }
        while pending.count < 2 { await Task.yield() }

        pending[0].resume()
        await first.value
        #expect(model.copied)

        pending[1].resume()
        await second.value
        #expect(!model.copied)
    }

    @Test func copyWithoutResultDoesNothing() async {
        var copied: [ClipboardContent] = []
        let model = AppModel.testing(
            polisher: FakePolisher(),
            writeToPasteboard: { copied.append($0) },
            sleep: { _ in }
        )

        await model.copyResult()

        #expect(copied.isEmpty)
        #expect(!model.copied)
    }

    @Test func formattedInputIsSentAsMarkdown() async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.input = richText("Make it **bold** and *calm* 🙂\n- one\n- two")

        await model.process()

        #expect(polisher.calls.first?.text == "Make it **bold** and *calm* 🙂\n- one\n- two")
    }

    @Test func outputIsSetFromTheResultMarkdown() async {
        let model = makeModel(FakePolisher())
        model.input = NSAttributedString(string: "Hello")

        await model.process()

        #expect(markdown(model.output) == PolishResult.sample.polishedText)
        #expect(model.output.string.contains("• Read the summary"))
    }

    @Test func failureLeavesOutputEmpty() async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")
        await model.process()

        polisher.outcome = .failure(.claudeNotFound)
        await model.process()

        #expect(model.output.length == 0)
    }

    @Test func copyUsesTheEditedOutput() async {
        var copied: [ClipboardContent] = []
        let model = AppModel.testing(
            polisher: FakePolisher(),
            writeToPasteboard: { copied.append($0) },
            sleep: { _ in }
        )
        model.input = NSAttributedString(string: "Hello")
        await model.process()
        model.output = richText("My **edit** & [more](https://x.com)\n- point")

        await model.copyResult()

        #expect(copied.count == 1)
        #expect(copied.first?.html.contains("<b>edit</b> &amp; ") == true)
        #expect(copied.first?.html.contains("<ul><li>point</li></ul>") == true)
        #expect(copied.first?.plain == "My edit & more (https://x.com)\n• point")
    }

    @Test func clearEmptiesInputOutputResultAndError() async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")
        await model.process()
        model.showStartupError(PolishError.claudeNotFound)

        model.clear(undoManager: nil)

        #expect(model.input.length == 0)
        #expect(model.output.length == 0)
        #expect(model.result == nil)
        #expect(model.errorMessage == nil)
        #expect(!model.canClear)
    }

    @Test func clearWhileLoadingDoesNothing() async {
        let model = makeModel(FakePolisher(delay: .milliseconds(200)))
        model.input = NSAttributedString(string: "Hello")
        let request = Task { await model.process() }
        while !model.isLoading { await Task.yield() }

        #expect(!model.canClear)
        model.clear(undoManager: nil)

        #expect(model.input.string == "Hello")
        await request.value
        #expect(model.result == .sample)
    }

    @Test func canClearIsFalseWhenEverythingIsEmpty() {
        #expect(!makeModel(FakePolisher()).canClear)
    }

    @Test func canClearWithOnlyInput() {
        let model = makeModel(FakePolisher())
        model.input = NSAttributedString(string: "Hello")
        #expect(model.canClear)
    }

    @Test func canClearWithOnlyAnError() async {
        let model = makeModel(FakePolisher())
        await model.process()
        #expect(model.errorMessage != nil)
        #expect(model.canClear)
    }

    @Test func canClearAfterAResultEvenWithEmptyInput() async {
        let model = makeModel(FakePolisher())
        model.input = NSAttributedString(string: "Hello")
        await model.process()
        model.input = NSAttributedString()
        #expect(model.canClear)
    }

    private static let newerResult = PolishResult(
        polishedText: "The newer answer.",
        learningSummary: nil,
        detectedLanguage: "English",
        wasTranslated: false,
        modelUsed: ModelRouting.haikuModel
    )

    private func waitUntil(_ polisher: GatedPolisher, hasCalls count: Int) async {
        while polisher.waitingCount < count { await Task.yield() }
    }

    @Test func startProcessingShowsLoadingRightAway() async {
        let polisher = GatedPolisher()
        let gated = AppModel.testing(polisher: polisher)
        gated.input = NSAttributedString(string: "Hello")

        gated.startProcessing()
        gated.startProcessing()

        #expect(gated.isLoading)
        await waitUntil(polisher, hasCalls: 1)
        polisher.resume(0, with: .success(.sample))
        await gated.requests.task?.value
        #expect(polisher.waitingCount == 1)
        #expect(gated.result == .sample)
        #expect(!gated.isLoading)
    }

    @Test func cancelEndsLoadingWithoutErrorOrResult() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)

        model.cancel()

        #expect(!model.isLoading)
        #expect(polisher.cancelledCount == 1)
        polisher.resume(0, with: .failure(.cliFailed(stderr: "Cancelled")))
        await model.requests.task?.value
        #expect(model.errorMessage == nil)
        #expect(model.result == nil)
        #expect(model.output.length == 0)
        #expect(model.input.string == "Hello")
    }

    @Test func cancelledTaskShowsNoErrorEvenWithoutCancelCall() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        let request = Task { await model.process() }
        await waitUntil(polisher, hasCalls: 1)

        request.cancel()
        polisher.resume(0, with: .failure(.cliFailed(stderr: "Cancelled")))
        await request.value

        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
        #expect(model.result == nil)
    }

    @Test func newRequestAfterCancelWorksAndIgnoresTheLateAnswer() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)
        let cancelled = model.requests.task
        model.cancel()

        model.startProcessing()
        await waitUntil(polisher, hasCalls: 2)
        polisher.resume(1, with: .success(Self.newerResult))
        await model.requests.task?.value
        polisher.resume(0, with: .success(.sample))
        await cancelled?.value

        #expect(model.result == Self.newerResult)
        #expect(model.output.string == "The newer answer.")
        #expect(!model.isLoading)
    }

    @Test func lateFailureOfACancelledRequestDoesNotTouchTheNewerOne() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)
        let cancelled = model.requests.task
        model.cancel()
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 2)
        let newer = model.requests.task

        polisher.resume(0, with: .failure(.cliFailed(stderr: "Cancelled")))
        await cancelled?.value

        #expect(model.isLoading)
        #expect(model.errorMessage == nil)
        polisher.resume(1, with: .success(Self.newerResult))
        await newer?.value
        #expect(model.result == Self.newerResult)
    }

    @Test func cancelWhenIdleKeepsTheResult() async {
        let model = makeModel(FakePolisher())
        model.input = NSAttributedString(string: "Hello")
        await model.process()

        model.cancel()

        #expect(model.result == .sample)
        #expect(model.output.length > 0)
    }
}
