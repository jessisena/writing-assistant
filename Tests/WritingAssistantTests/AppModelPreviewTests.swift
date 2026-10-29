import AppKit
import Foundation
import Testing
import WritingAssistantCore

@testable import WritingAssistant

/// A polish that shows its polished text before the learning summary arrives.
@MainActor
@Suite struct AppModelPreviewTests {
    private let directory = makeTemporaryDirectory()

    private static let preview = PolishPreview(
        polishedText: "Preview text.", detectedLanguage: "English", wasTranslated: false)

    private var logURL: URL { directory.appending(path: "learning-log.md") }

    private func makeModel(
        _ polisher: any Polishing,
        writeToPasteboard: @escaping @MainActor (ClipboardContent) -> Void = { _ in }
    ) -> AppModel {
        AppModel.testing(
            polisher: polisher, directory: directory, writeToPasteboard: writeToPasteboard)
    }

    private func markdown(_ text: NSAttributedString) -> String {
        RichText.markdown(from: RichTextBridge.attributedString(from: text))
    }

    /// Yields until `condition` holds, so main-actor hops from the preview callback can run.
    /// Gives up after a while, so a broken test fails instead of hanging.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }

    /// Yields long enough for any pending main-actor hop to run.
    private func settle() async {
        for _ in 0..<200 {
            await Task.yield()
        }
    }

    /// Starts polishing "Hello" and waits until the polisher has the call.
    private func start(_ model: AppModel, _ polisher: GatedPolisher, calls: Int = 1) async {
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil { polisher.waitingCount >= calls }
    }

    /// Starts polishing and sends `preview`, waiting until it is on screen.
    private func startWithPreview(
        _ model: AppModel, _ polisher: GatedPolisher, preview: PolishPreview = Self.preview
    ) async {
        await start(model, polisher)
        polisher.sendPreview(0, preview)
        await waitUntil { model.result != nil }
    }

    @Test func previewShowsThePolishedTextWhileTheSummaryIsComing() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)

        await startWithPreview(model, polisher)

        let result = try #require(model.result)
        #expect(result.polishedText == "Preview text.")
        #expect(result.learningSummary == nil)
        #expect(result.detectedLanguage == "English")
        #expect(result.modelUsed == ModelRouting.pickModel(for: "Hello"))
        #expect(model.output.string == "Preview text.")
        #expect(model.isAwaitingSummary)
        #expect(model.isLoading)
        #expect(!model.canRefine)
        #expect(!model.canClear)
        #expect(model.history.isEmpty)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func finalResultAddsTheSummaryAndKeepsThePreviewOutput() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await startWithPreview(model, polisher)

        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value

        #expect(model.result == .sample)
        #expect(model.output.string == "Preview text.")
        #expect(!model.isAwaitingSummary)
        #expect(!model.isLoading)
        #expect(model.history.count == 1)
        #expect(model.history[0].learningSummary == PolishResult.sample.learningSummary)
        #expect(model.history[0].outputMarkdown == "Preview text.")
        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.components(separatedBy: "### Corrections").count == 2)
    }

    @Test func finalResultWithoutAPreviewFillsTheOutput() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)

        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value

        #expect(model.result == .sample)
        #expect(markdown(model.output) == PolishResult.sample.polishedText)
        #expect(!model.isAwaitingSummary)
        #expect(model.history.count == 1)
    }

    @Test func previewSentJustBeforeTheAnswerIsRecordedOnce() async throws {
        let preview = PolishPreview(
            polishedText: PolishResult.sample.polishedText, detectedLanguage: nil,
            wasTranslated: nil)
        let model = makeModel(FakePolisher(preview: preview))
        model.input = NSAttributedString(string: "Hello")

        await model.process()
        await settle()

        #expect(model.result == .sample)
        #expect(!model.isAwaitingSummary)
        #expect(model.history.count == 1)
        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.components(separatedBy: "### Corrections").count == 2)
    }

    @Test func previewWithoutLanguageFieldsShowsUnknownLanguage() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        let preview = PolishPreview(
            polishedText: "Preview text.", detectedLanguage: nil, wasTranslated: nil)

        await startWithPreview(model, polisher, preview: preview)

        let result = try #require(model.result)
        #expect(result.detectedLanguage == "Unknown")
        #expect(!result.wasTranslated)
        #expect(model.isAwaitingSummary)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func secondPreviewOfTheSameRequestIsIgnored() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await startWithPreview(model, polisher)

        polisher.sendPreview(
            0, PolishPreview(polishedText: "Other.", detectedLanguage: nil, wasTranslated: nil))
        await settle()

        #expect(model.output.string == "Preview text.")
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func previewAfterTheFinalResultIsIgnored() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value

        polisher.sendPreview(0, Self.preview)
        await settle()

        #expect(model.result == .sample)
        #expect(markdown(model.output) == PolishResult.sample.polishedText)
        #expect(!model.isAwaitingSummary)
    }

    @Test func previewAfterCancelIsIgnored() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)
        let cancelled = model.requests.task
        model.cancel()

        polisher.sendPreview(0, Self.preview)
        await settle()

        #expect(model.result == nil)
        #expect(model.output.length == 0)
        #expect(!model.isAwaitingSummary)
        polisher.resume(0, with: .success(.sample))
        await cancelled?.value
        #expect(model.history.isEmpty)
    }

    @Test func previewOfACancelledRequestDoesNotReachTheNewerOne() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)
        let cancelled = model.requests.task
        model.cancel()
        model.startProcessing()
        await waitUntil { polisher.waitingCount >= 2 }

        polisher.sendPreview(0, Self.preview)
        await settle()

        #expect(model.result == nil)
        polisher.resume(0, with: .success(.sample))
        await cancelled?.value
        polisher.resume(1, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.result == .sample)
    }

    @Test func translatedPreviewDoesNotWaitForASummary() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        let preview = PolishPreview(
            polishedText: "Hello.", detectedLanguage: "Spanish", wasTranslated: true)

        await startWithPreview(model, polisher, preview: preview)

        let result = try #require(model.result)
        #expect(result.wasTranslated)
        #expect(result.detectedLanguage == "Spanish")
        #expect(!model.isAwaitingSummary)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func previewWithTheSummaryOffDoesNotWaitForOne() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        model.includesLearningSummary = false

        await startWithPreview(model, polisher)

        #expect(model.result != nil)
        #expect(!model.isAwaitingSummary)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func editsMadeWhileWaitingSurviveTheFinalResult() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await startWithPreview(model, polisher)
        model.output = NSAttributedString(string: "My edit")

        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value

        #expect(model.output.string == "My edit")
        #expect(model.history[0].outputMarkdown == "My edit")
    }

    @Test func showChangesSurvivesTheFinalResult() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await startWithPreview(model, polisher)
        model.showsChanges = true

        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value

        #expect(model.showsChanges)
    }

    @Test func cancelAfterAPreviewKeepsTheTextAndRecordsItWithoutASummary() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await startWithPreview(model, polisher)
        let cancelled = model.requests.task
        model.output = NSAttributedString(string: "My edit")

        model.cancel()

        #expect(!model.isLoading)
        #expect(!model.isAwaitingSummary)
        #expect(model.errorMessage == nil)
        #expect(model.output.string == "My edit")
        #expect(model.result?.polishedText == "Preview text.")
        #expect(model.history.count == 1)
        #expect(model.history[0].learningSummary == nil)
        #expect(model.history[0].outputMarkdown == "My edit")
        #expect(model.currentHistoryID == model.history[0].id)
        polisher.resume(0, with: .success(.sample))
        await cancelled?.value
        #expect(model.history.count == 1)
        #expect(model.result?.learningSummary == nil)
        #expect(!FileManager.default.fileExists(atPath: logURL.path))
    }

    @Test func failureAfterAPreviewKeepsTheTextAndShowsTheError() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await startWithPreview(model, polisher)

        polisher.resume(0, with: .failure(.timeout(seconds: 60)))
        await model.requests.task?.value

        #expect(model.errorMessage == PolishError.timeout(seconds: 60).errorDescription)
        #expect(model.output.string == "Preview text.")
        #expect(model.result?.polishedText == "Preview text.")
        #expect(!model.isAwaitingSummary)
        #expect(model.history.count == 1)
        #expect(model.history[0].learningSummary == nil)
        #expect(!FileManager.default.fileExists(atPath: logURL.path))
    }

    @Test func cancelledTaskAfterAPreviewRecordsIt() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")
        let request = Task { await model.process() }
        await waitUntil { polisher.waitingCount >= 1 }
        polisher.sendPreview(0, Self.preview)
        await waitUntil { model.result != nil }

        request.cancel()
        polisher.resume(0, with: .success(.sample))
        await request.value

        #expect(model.errorMessage == nil)
        #expect(!model.isAwaitingSummary)
        #expect(model.history.count == 1)
        #expect(model.history[0].learningSummary == nil)
    }

    @Test func copyWorksWhileTheSummaryIsComing() async {
        let polisher = GatedPolisher()
        var copies: [ClipboardContent] = []
        let model = makeModel(polisher) { copies.append($0) }
        await startWithPreview(model, polisher)

        await model.copyResult()

        #expect(copies.map(\.plain) == ["Preview text."])
        #expect(model.isAwaitingSummary)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }
}
