import AppKit
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelChannelPersistenceTests {
    private func makeDefaults() -> UserDefaults {
        TestDefaults.make()
    }

    @Test func selectedChannelSurvivesANewModel() {
        let defaults = makeDefaults()
        AppModel.testing(polisher: FakePolisher(), defaults: defaults).channel = .slackInformal

        let relaunched = AppModel.testing(polisher: FakePolisher(), defaults: defaults)

        #expect(relaunched.channel == .slackInformal)
    }

    @Test func unknownSavedChannelFallsBackToFormal() {
        let defaults = makeDefaults()
        defaults.set("telegram", forKey: AppModel.channelDefaultsKey)

        let model = AppModel.testing(polisher: FakePolisher(), defaults: defaults)

        #expect(model.channel == .formal)
    }

    @Test func modelsWithSeparateSuitesDoNotShareTheChannel() {
        AppModel.testing(polisher: FakePolisher()).channel = .aiPrompt

        #expect(AppModel.testing(polisher: FakePolisher()).channel == .formal)
    }

    @Test func restoringAHistoryEntryKeepsItsChannelForNextLaunch() async {
        let defaults = makeDefaults()
        let model = AppModel.testing(polisher: FakePolisher(), defaults: defaults)
        model.channel = .slack
        model.input = NSAttributedString(string: "Hello")
        await model.process()
        model.channel = .talkingPoints

        model.restoreHistoryEntry(id: model.history[0].id)

        let relaunched = AppModel.testing(polisher: FakePolisher(), defaults: defaults)
        #expect(relaunched.channel == .slack)
    }
}

@MainActor
@Suite struct LearningSummarySettingTests {
    @Test func isOnWhenNothingWasSaved() {
        #expect(AppModel.testing(polisher: FakePolisher()).includesLearningSummary)
    }

    @Test func turningItOffSurvivesANewModel() {
        let defaults = TestDefaults.make()
        AppModel.testing(polisher: FakePolisher(), defaults: defaults)
            .includesLearningSummary = false

        let relaunched = AppModel.testing(polisher: FakePolisher(), defaults: defaults)

        #expect(!relaunched.includesLearningSummary)
        #expect(defaults.object(forKey: AppModel.learningSummaryDefaultsKey) as? Bool == false)
    }

    @Test func eachPolishAsksForTheSummaryAsTheSettingSays() async {
        let polisher = FakePolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")

        await model.process()
        model.includesLearningSummary = false
        await model.process()

        #expect(polisher.summaryRequests == [true, false])
    }
}

@MainActor
@Suite struct RequestStartedAtTests {
    private func waitUntil(_ polisher: GatedPolisher, hasCalls count: Int) async {
        while polisher.waitingCount < count { await Task.yield() }
    }

    @Test func isNilBeforeAnyRequest() {
        #expect(AppModel.testing(polisher: FakePolisher()).requestStartedAt == nil)
    }

    @Test func isSetWhilePolishingAndClearedWhenItFinishes() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        let before = Date.now

        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)

        let startedAt = model.requestStartedAt
        #expect(startedAt != nil && startedAt! >= before)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.requestStartedAt == nil)
    }

    @Test func isClearedWhenThePolishFails() async {
        let model = AppModel.testing(
            polisher: FakePolisher(outcome: .failure(.claudeNotFound)))
        model.input = NSAttributedString(string: "Hello")

        await model.process()

        #expect(model.requestStartedAt == nil)
    }

    @Test func isClearedWhenCancelled() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)
        let cancelled = model.requests.task

        model.cancel()

        #expect(model.requestStartedAt == nil)
        polisher.resume(0, with: .success(.sample))
        await cancelled?.value
        #expect(model.requestStartedAt == nil)
    }

    @Test func lateAnswerOfACancelledRequestKeepsTheNewerRequestsStart() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)
        let cancelled = model.requests.task
        model.cancel()
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 2)

        polisher.resume(0, with: .success(.sample))
        await cancelled?.value

        #expect(model.requestStartedAt != nil)
        polisher.resume(1, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.requestStartedAt == nil)
    }

    @Test func isSetWhileRefiningAndClearedWhenItFinishes() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil(polisher, hasCalls: 1)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value

        model.refine(.shorter)
        await waitUntil(polisher, hasCalls: 2)

        #expect(model.requestStartedAt != nil)
        polisher.resume(1, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.requestStartedAt == nil)
    }
}

@MainActor
@Suite struct UndoableClearTests {
    private func polishedModel() async -> AppModel {
        let model = AppModel.testing(polisher: FakePolisher())
        model.input = NSAttributedString(string: "Hello there")
        await model.process()
        return model
    }

    @Test func undoRestoresInputOutputAndResult() async {
        let model = await polishedModel()
        let input = model.input
        let output = model.output
        let undoManager = UndoManager()

        model.clear(undoManager: undoManager)
        #expect(model.input.length == 0)
        undoManager.undo()

        #expect(model.input == input)
        #expect(model.output == output)
        #expect(model.result == .sample)
    }

    @Test func undoActionIsNamedClear() async {
        let model = await polishedModel()
        let undoManager = UndoManager()

        model.clear(undoManager: undoManager)

        #expect(undoManager.undoActionName == "Clear")
    }

    @Test func undoRestoresTheErrorBanner() {
        let model = AppModel.testing(polisher: FakePolisher())
        model.input = NSAttributedString(string: "Hello")
        model.showBanner("Disk full")
        let undoManager = UndoManager()

        model.clear(undoManager: undoManager)
        #expect(model.errorMessage == nil)
        undoManager.undo()

        #expect(model.errorMessage == "Disk full")
    }

    @Test func undoKeepsSavingEditsToTheSameHistoryEntry() async {
        let model = await polishedModel()
        let entryID = model.currentHistoryID
        let undoManager = UndoManager()

        model.clear(undoManager: undoManager)
        #expect(model.currentHistoryID == nil)
        undoManager.undo()

        #expect(model.currentHistoryID == entryID)
    }

    @Test func undoKeepsEditsMadeToNewerWorkAfterTheClear() async {
        let model = await polishedModel()
        let undoManager = UndoManager()
        model.clear(undoManager: undoManager)
        model.input = NSAttributedString(string: "Newer text")
        await model.process()
        let newerID = model.currentHistoryID
        model.output = NSAttributedString(string: "Edited newer output")

        undoManager.undo()

        let newer = model.history.first { $0.id == newerID }
        #expect(newer?.outputMarkdown == "Edited newer output")
        #expect(model.currentHistoryID != newerID)
    }

    @Test func clearWithoutAnUndoManagerStillClears() async {
        let model = await polishedModel()

        model.clear(undoManager: nil)

        #expect(model.input.length == 0)
        #expect(model.output.length == 0)
        #expect(model.result == nil)
    }

    @Test func clearWhileLoadingRegistersNoUndo() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        while polisher.waitingCount < 1 { await Task.yield() }
        let undoManager = UndoManager()

        model.clear(undoManager: undoManager)

        #expect(!undoManager.canUndo)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func undoDuringARequestLeavesTheRunningRequestAlone() async {
        let polisher = GatedPolisher()
        let model = AppModel.testing(polisher: polisher)
        model.input = NSAttributedString(string: "Hello")
        let undoManager = UndoManager()
        model.clear(undoManager: undoManager)
        model.input = NSAttributedString(string: "New text")
        model.startProcessing()
        while polisher.waitingCount < 1 { await Task.yield() }

        undoManager.undo()

        #expect(model.input.string == "New text")
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }
}
