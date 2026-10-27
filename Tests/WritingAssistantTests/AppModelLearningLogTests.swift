import AppKit
import Foundation
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelLearningLogTests {
    private let directory = makeTemporaryDirectory()

    private var logURL: URL { directory.appending(path: "learning-log.md") }

    private func logText() -> String? {
        try? String(contentsOf: logURL, encoding: .utf8)
    }

    private func process(_ outcome: Result<PolishResult, PolishError>) async -> AppModel {
        let model = AppModel.testing(polisher: FakePolisher(outcome: outcome), directory: directory)
        model.input = NSAttributedString(string: "I will to review the doc")
        await model.process()
        return model
    }

    @Test func refineDoesNotAppend() async throws {
        let model = await process(.success(.sample))
        let before = try #require(logText())

        model.refine(.moreFormal)
        await model.requestTask?.value

        #expect(logText() == before)
    }

    @Test func successWithSummaryAppendsOneEntry() async throws {
        let model = await process(.success(.sample))

        let text = try #require(logText())
        #expect(text.components(separatedBy: "### Corrections").count == 2)
        #expect(text.contains("I will to review → I'll review"))
        #expect(text.contains(Channel.formal.displayName))
        #expect(model.errorMessage == nil)
    }

    @Test func twoRequestsAppendTwoEntries() async throws {
        let model = AppModel.testing(polisher: FakePolisher(), directory: directory)
        model.input = NSAttributedString(string: "I will to review the doc")
        await model.process()
        await model.process()

        let text = try #require(logText())
        #expect(text.components(separatedBy: "### Corrections").count == 3)
    }

    @Test func missingSummaryWritesNothing() async {
        var translated = PolishResult.sample
        translated.learningSummary = nil
        translated.wasTranslated = true

        _ = await process(.success(translated))

        #expect(logText() == nil)
    }

    @Test func emptySummaryWritesNothing() async {
        var clean = PolishResult.sample
        clean.learningSummary = LearningSummary(corrections: [], grammarInsight: "", vocabulary: [])

        _ = await process(.success(clean))

        #expect(logText() == nil)
    }

    @Test func failedRequestWritesNothing() async {
        _ = await process(.failure(.claudeNotFound))

        #expect(logText() == nil)
    }

    @Test func writeFailureShowsBannerAndKeepsResult() async throws {
        let blocker = directory.appending(path: "not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let model = AppModel.testing(polisher: FakePolisher(), directory: blocker)
        model.input = NSAttributedString(string: "I will to review the doc")

        await model.process()

        #expect(model.result == .sample)
        #expect(model.output.length > 0)
        let message = try #require(model.errorMessage)
        #expect(message.contains("Couldn't write the learning log"))
    }

    @Test func openingAnExistingLogOpensTheFile() async {
        let model = await process(.success(.sample))
        var opened: [URL] = []

        model.openLearningLog { opened.append($0) }

        #expect(opened == [logURL])
        #expect(model.errorMessage == nil)
    }

    @Test func openingAMissingLogExplainsWhyOnce() {
        let model = AppModel.testing(polisher: FakePolisher(), directory: directory)
        var opened: [URL] = []

        model.openLearningLog { opened.append($0) }
        model.openLearningLog { opened.append($0) }

        #expect(opened.isEmpty)
        #expect(model.errorMessage == LearningLogMissing(path: logURL.path).errorDescription)
    }
}
