import AppKit
import Foundation
import Testing
import WritingAssistantCore

@testable import WritingAssistant

/// A polish that shows its polished text as it streams in, before the learning summary arrives.
@MainActor
@Suite struct AppModelPreviewTests {
    private let directory = makeTemporaryDirectory()

    private static let preview = PolishPreview(
        polishedText: "Preview text.", isTextComplete: true, detectedLanguage: "English",
        wasTranslated: false)

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

    /// Waits until `condition` holds, so main-actor hops from the preview callback (which may
    /// wait out `AppModel.previewInterval`) can run. Gives up after two seconds, so a broken
    /// test fails instead of hanging.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Waits long enough for any pending preview delivery to run.
    private func settle() async {
        try? await Task.sleep(for: AppModel.previewInterval * 4)
    }

    /// Starts polishing "Hello" and waits until the polisher has the call.
    private func start(_ model: AppModel, _ polisher: GatedPolisher, calls: Int = 1) async {
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        await waitUntil { polisher.waitingCount >= calls }
    }

    /// Sends `preview` to the first call and waits until its text is in the output.
    private func send(_ preview: PolishPreview, to model: AppModel, _ polisher: GatedPolisher) async
    {
        polisher.sendPreview(0, preview)
        await waitUntil { model.result?.polishedText == preview.polishedText }
    }

    /// Starts polishing and sends `preview`, waiting until it is on screen.
    private func startWithPreview(
        _ model: AppModel, _ polisher: GatedPolisher, preview: PolishPreview = Self.preview
    ) async {
        await start(model, polisher)
        await send(preview, to: model, polisher)
    }

    private func partial(
        _ text: String, language: String? = "English", translated: Bool? = false
    ) -> PolishPreview {
        PolishPreview(polishedText: text, detectedLanguage: language, wasTranslated: translated)
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
        #expect(!model.isStreamingText)
        #expect(model.polishStage == .writingTips)
        #expect(model.isLoading)
        #expect(!model.canRefine)
        #expect(!model.canClear)
        #expect(model.history.isEmpty)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func streamedTextGrowsReadOnlyUntilItIsComplete() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)

        await send(partial("Prev"), to: model, polisher)

        #expect(model.output.string == "Prev")
        #expect(model.isStreamingText)
        #expect(model.isAwaitingSummary)
        #expect(model.polishStage == .polishing)
        #expect(model.history.isEmpty)

        await send(partial("Preview te"), to: model, polisher)
        #expect(model.output.string == "Preview te")
        #expect(model.isStreamingText)

        await send(Self.preview, to: model, polisher)
        #expect(model.output.string == "Preview text.")
        #expect(!model.isStreamingText)
        #expect(model.polishStage == .writingTips)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.output.string == "Preview text.")
        #expect(model.polishStage == nil)
    }

    @Test func aBurstOfPreviewsEndsWithTheNewest() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)
        let words = (1...200).map { "w\($0)" }

        for count in 1...words.count {
            polisher.sendPreview(0, partial(words.prefix(count).joined(separator: " ")))
        }
        await waitUntil { model.output.string.hasSuffix("w200") }

        #expect(model.output.string == words.joined(separator: " "))
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func previewWithoutTextYetLeavesTheSkeleton() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)

        polisher.sendPreview(0, PolishPreview(polishedText: "", wasTranslated: false))
        await waitUntil { model.polishStage == .polishing }

        #expect(model.result == nil)
        #expect(model.output.length == 0)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func stageFollowsATranslation() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)
        #expect(model.polishStage == .detectingLanguage)

        polisher.sendPreview(0, PolishPreview(detectedLanguage: "Spanish"))
        await settle()
        #expect(model.polishStage == .detectingLanguage)
        polisher.sendPreview(0, PolishPreview(detectedLanguage: "Spanish", wasTranslated: true))
        await waitUntil { model.polishStage == .translating(from: "Spanish") }
        #expect(model.result == nil)

        await send(partial("Hel", language: "Spanish", translated: true), to: model, polisher)
        #expect(model.polishStage == .translating(from: "Spanish"))
        #expect(!model.isAwaitingSummary)

        await send(
            PolishPreview(
                polishedText: "Hello.", isTextComplete: true, detectedLanguage: "Spanish",
                wasTranslated: true), to: model, polisher)
        #expect(model.polishStage == .finishing)
        #expect(!model.isAwaitingSummary)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.polishStage == nil)
    }

    @Test func summaryOffNeverWritesTips() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        model.includesLearningSummary = false
        await start(model, polisher)

        await send(partial("Prev"), to: model, polisher)
        #expect(model.polishStage == .polishing)
        await send(Self.preview, to: model, polisher)

        #expect(model.polishStage == .finishing)
        #expect(!model.isAwaitingSummary)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func textBeforeTheLanguageReadsAsPolishingAndTakesTheLanguageLater() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)

        await send(partial("Bonj", language: nil, translated: nil), to: model, polisher)
        #expect(model.polishStage == .polishing)
        #expect(model.result?.detectedLanguage == "Unknown")

        await send(PolishPreview(polishedText: "Hello.", isTextComplete: true), to: model, polisher)
        #expect(model.polishStage == .writingTips)
        #expect(model.isAwaitingSummary)
        model.output = NSAttributedString(string: "My edit")

        polisher.sendPreview(
            0,
            PolishPreview(
                polishedText: "Hello.", isTextComplete: true, detectedLanguage: "French",
                wasTranslated: true))
        await waitUntil { model.result?.wasTranslated == true }

        let result = try #require(model.result)
        #expect(result.detectedLanguage == "French")
        #expect(!model.isAwaitingSummary)
        #expect(model.polishStage == .finishing)
        #expect(model.output.string == "My edit")
        let cancelled = model.requests.task
        model.cancel()
        #expect(model.history.first?.detectedLanguage == "French")
        polisher.resume(0, with: .success(.sample))
        await cancelled?.value
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

    @Test func finalResultReplacesTextThatWasStillStreaming() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)
        await send(partial("Thanks for"), to: model, polisher)

        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value

        #expect(model.result == .sample)
        #expect(markdown(model.output) == PolishResult.sample.polishedText)
        #expect(!model.isStreamingText)
        #expect(model.history.count == 1)
        #expect(model.history[0].outputMarkdown == PolishResult.sample.polishedText)
    }

    @Test func previewsSentJustBeforeTheAnswerAreRecordedOnce() async throws {
        let text = PolishResult.sample.polishedText
        let previews = [
            PolishPreview(polishedText: String(text.prefix(10))),
            PolishPreview(polishedText: text, isTextComplete: true),
        ]
        let model = makeModel(FakePolisher(previews: previews))
        model.input = NSAttributedString(string: "Hello")

        await model.process()
        await settle()

        #expect(model.result == .sample)
        #expect(!model.isAwaitingSummary)
        #expect(!model.isStreamingText)
        #expect(model.polishStage == nil)
        #expect(model.history.count == 1)
        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.components(separatedBy: "### Corrections").count == 2)
    }

    @Test func previewWithoutLanguageFieldsShowsUnknownLanguage() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        let preview = PolishPreview(polishedText: "Preview text.", isTextComplete: true)

        await startWithPreview(model, polisher, preview: preview)

        let result = try #require(model.result)
        #expect(result.detectedLanguage == "Unknown")
        #expect(!result.wasTranslated)
        #expect(model.isAwaitingSummary)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }

    @Test func otherTextAfterTheCompleteTextIsIgnored() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await startWithPreview(model, polisher)

        polisher.sendPreview(0, PolishPreview(polishedText: "Other.", isTextComplete: true))
        await settle()

        #expect(model.output.string == "Preview text.")
        #expect(model.result?.polishedText == "Preview text.")
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
        #expect(model.polishStage == nil)
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
        #expect(model.polishStage == nil)
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
        #expect(model.polishStage == .detectingLanguage)
        polisher.resume(0, with: .success(.sample))
        await cancelled?.value
        #expect(model.polishStage == .detectingLanguage)
        polisher.resume(1, with: .success(.sample))
        await model.requests.task?.value
        #expect(model.result == .sample)
    }

    @Test func translatedPreviewDoesNotWaitForASummary() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        let preview = PolishPreview(
            polishedText: "Hello.", isTextComplete: true, detectedLanguage: "Spanish",
            wasTranslated: true)

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

    @Test func editsMadeAfterTheTextIsCompleteSurviveTheFinalResult() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)
        await send(partial("Prev"), to: model, polisher)
        await send(Self.preview, to: model, polisher)
        model.output = NSAttributedString(string: "My edit")

        polisher.sendPreview(0, Self.preview)
        await settle()
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
        #expect(model.polishStage == nil)
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

    @Test func cancelWhileTheTextIsStreamingClearsItAndRecordsNothing() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)
        await send(partial("Prev"), to: model, polisher)
        let cancelled = model.requests.task

        model.cancel()

        #expect(model.result == nil)
        #expect(model.output.length == 0)
        #expect(!model.isStreamingText)
        #expect(!model.isAwaitingSummary)
        #expect(model.history.isEmpty)
        polisher.sendPreview(0, Self.preview)
        polisher.resume(0, with: .success(.sample))
        await cancelled?.value
        await settle()
        #expect(model.result == nil)
        #expect(model.history.isEmpty)
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

    @Test func failureWhileTheTextIsStreamingClearsItAndShowsTheError() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        await start(model, polisher)
        await send(partial("Prev"), to: model, polisher)

        polisher.resume(0, with: .failure(.badFormat(detail: "x")))
        await model.requests.task?.value

        #expect(model.errorMessage == PolishError.badFormat(detail: "x").errorDescription)
        #expect(model.result == nil)
        #expect(model.output.length == 0)
        #expect(!model.isStreamingText)
        #expect(model.polishStage == nil)
        #expect(model.history.isEmpty)
    }

    @Test func cancelledTaskAfterAPreviewRecordsIt() async {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")
        let request = Task { await model.process() }
        await waitUntil { polisher.waitingCount >= 1 }
        await send(Self.preview, to: model, polisher)

        request.cancel()
        polisher.resume(0, with: .success(.sample))
        await request.value

        #expect(model.errorMessage == nil)
        #expect(!model.isAwaitingSummary)
        #expect(model.history.count == 1)
        #expect(model.history[0].learningSummary == nil)
    }

    @Test func copyWaitsForTheCompleteTextAndThenWorksWhileTheSummaryIsComing() async {
        let polisher = GatedPolisher()
        var copies: [ClipboardContent] = []
        let model = makeModel(polisher) { copies.append($0) }
        await start(model, polisher)
        await send(partial("Prev"), to: model, polisher)

        await model.copyResult()
        #expect(copies.isEmpty)
        #expect(!model.copied)

        await send(Self.preview, to: model, polisher)
        await model.copyResult()

        #expect(copies.map(\.plain) == ["Preview text."])
        #expect(model.isAwaitingSummary)
        polisher.resume(0, with: .success(.sample))
        await model.requests.task?.value
    }
}
