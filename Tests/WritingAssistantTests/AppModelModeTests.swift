import AppKit
import Foundation
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelModeTests {
    private let directory = makeTemporaryDirectory()

    private func makeModel(
        _ polisher: any Polishing, defaults: UserDefaults = TestDefaults.make()
    ) -> AppModel {
        AppModel.testing(polisher: polisher, directory: directory, defaults: defaults)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func switchingIsInstantAndChangesTheChipsAndChannel() {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hola")

        model.switchMode(to: .personal)

        #expect(model.mode == .personal)
        #expect(model.visibleChannels == [.personalMessage, .email, .proofread, .other])
        #expect(model.channel == .personalMessage)
        #expect(!model.includesLearningSummary)
        #expect(polisher.calls.isEmpty)
        #expect(model.input.string == "Hola")
    }

    @Test func toggleAlternatesAndEachModeKeepsItsChannel() {
        let model = makeModel(FakePolisher())
        model.channel = .aiPrompt
        model.toggleMode()
        model.channel = .other

        model.toggleMode()

        #expect(model.mode == .work)
        #expect(model.channel == .aiPrompt)
        model.toggleMode()
        #expect(model.channel == .other)
    }

    @Test func modeAndChannelsSurviveANewModel() {
        let defaults = TestDefaults.make()
        let model = makeModel(FakePolisher(), defaults: defaults)
        model.channel = .talkingPoints
        model.switchMode(to: .personal)
        model.channel = .proofread

        let relaunched = makeModel(FakePolisher(), defaults: defaults)

        #expect(relaunched.mode == .personal)
        #expect(relaunched.channel == .proofread)
        #expect(relaunched.modes[.work].channel == .talkingPoints)
    }

    @Test func eachPolishSendsTheCurrentModesOptions() async {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")

        await model.process()
        model.switchMode(to: .personal)
        await model.process()
        model.modes.setLearningSummary(false, for: .work)
        model.switchMode(to: .work)
        await model.process()

        #expect(
            polisher.requestedOptions == [
                PolishOptions(mode: .work, outputLanguage: .english, includesLearningSummary: true),
                PolishOptions(
                    mode: .personal, outputLanguage: .sameAsInput, includesLearningSummary: false),
                PolishOptions(
                    mode: .work, outputLanguage: .english, includesLearningSummary: false),
            ])
        #expect(polisher.calls.map(\.channel) == [.slack, .personalMessage, .slack])
    }

    @Test func modeCannotBeSwitchedWhileARequestRuns() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil { polisher.waitingCount == 1 }

        #expect(!model.canSwitchMode)
        model.toggleMode()
        model.switchMode(to: .personal)

        #expect(model.mode == .work)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.canSwitchMode)
    }

    @Test func historyRecordsTheModeAndRestoringSwitchesBack() async throws {
        let model = makeModel(FakePolisher())
        model.input = NSAttributedString(string: "Hello")
        await model.process()
        model.switchMode(to: .personal)
        model.channel = .other
        await model.process()

        #expect(model.history.map(\.mode) == [.personal, .work])
        #expect(model.historyEntries(in: .work).map(\.mode) == [.work])
        #expect(model.historyEntries(in: .personal).map(\.channel) == [.other])
        #expect(model.historyEntries(in: nil).count == 2)

        model.restoreHistoryEntry(id: model.history[1].id)

        #expect(model.mode == .work)
        #expect(model.channel == .slack)
    }

    @Test func restoringAnEntryWhoseChannelIsNowHiddenPicksTheFirstVisibleChip() async {
        let model = makeModel(FakePolisher())
        model.channel = .formal
        model.input = NSAttributedString(string: "Hello")
        await model.process()
        model.modes.setVisible(false, for: .formal, in: .work)
        model.switchMode(to: .personal)

        model.restoreHistoryEntry(id: model.history[0].id)

        #expect(model.mode == .work)
        #expect(model.channel == .slack)
    }

    @Test func spanishInSameAsInputNeverWaitsForTipsOrWritesTheLog() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        model.switchMode(to: .personal)
        model.modes.setLearningSummary(true, for: .personal)
        model.input = NSAttributedString(string: "hola, quedamos mañana?")
        model.startProcessing()
        await waitUntil { polisher.waitingCount == 1 }

        polisher.sendPreview(
            0,
            PolishPreview(
                polishedText: "Hola, ¿quedamos mañana?", isTextComplete: true,
                detectedLanguage: "Spanish", wasTranslated: false))
        await waitUntil { model.result != nil }

        #expect(model.polishStage == .finishing)
        #expect(!model.isAwaitingSummary)
        let final = PolishResult(
            polishedText: "Hola, ¿quedamos mañana?", learningSummary: nil,
            detectedLanguage: "Spanish", wasTranslated: false, modelUsed: ModelRouting.haikuModel)
        polisher.resume(0, with: .success(final))
        await model.requests.task?.value

        #expect(model.result?.learningSummary == nil)
        #expect(model.history.first?.mode == .personal)
        let logPath = directory.appending(path: "learning-log.md").path
        #expect(!FileManager.default.fileExists(atPath: logPath))
    }
}
