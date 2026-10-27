import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelTests {
    private func makeModel(_ polisher: FakePolisher) -> AppModel {
        AppModel(polisher: polisher, writeToPasteboard: { _ in }, sleep: { _ in })
    }

    @Test func defaultChannelIsFormal() {
        #expect(makeModel(FakePolisher()).channel == .formal)
    }

    @Test(arguments: ["", "   ", "\n\t  \n"])
    func blankInputShowsEmptyMessageWithoutCallingPolisher(input: String) async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.inputText = input

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

        model.inputText = "I will to review the doc"
        await model.process()

        #expect(model.result == .sample)
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
    }

    @Test(arguments: [PolishError.timeout(seconds: 120), .claudeNotFound])
    func failureClearsEarlierResultAndShowsMessage(error: PolishError) async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.inputText = "Hello"
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
        model.inputText = "  \n hola equipo \n "
        model.channel = .slackInformal

        await model.process()

        #expect(polisher.calls.count == 1)
        #expect(polisher.calls.first?.text == "hola equipo")
        #expect(polisher.calls.first?.channel == .slackInformal)
    }

    @Test func secondProcessWhileLoadingIsIgnored() async {
        let polisher = FakePolisher(delay: .milliseconds(200))
        let model = makeModel(polisher)
        model.inputText = "Hello"

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
        var copiedText: [String] = []
        var copiedDuringDelay: Bool?
        var waited: [Duration] = []
        var model: AppModel?
        model = AppModel(
            polisher: FakePolisher(),
            writeToPasteboard: { copiedText.append($0) },
            sleep: { duration in
                waited.append(duration)
                copiedDuringDelay = model?.copied
            }
        )
        guard let model else { return }
        model.inputText = "Hello"
        await model.process()

        await model.copyResult()

        #expect(copiedText == [PolishResult.sample.polishedText])
        #expect(copiedDuringDelay == true)
        #expect(waited == [.seconds(2)])
        #expect(!model.copied)
    }

    @Test func overlappingCopiesKeepCopiedUntilTheLastDelayEnds() async {
        var pending: [CheckedContinuation<Void, Never>] = []
        let model = AppModel(
            polisher: FakePolisher(),
            writeToPasteboard: { _ in },
            sleep: { _ in await withCheckedContinuation { pending.append($0) } }
        )
        model.inputText = "Hello"
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
        var copiedText: [String] = []
        let model = AppModel(
            polisher: FakePolisher(),
            writeToPasteboard: { copiedText.append($0) },
            sleep: { _ in }
        )

        await model.copyResult()

        #expect(copiedText.isEmpty)
        #expect(!model.copied)
    }
}
