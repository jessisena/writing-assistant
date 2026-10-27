import AppKit
import Foundation
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct AppModelHistoryTests {
    private let directory = makeTemporaryDirectory()

    private var store: HistoryStore {
        HistoryStore(fileURL: directory.appending(path: "history.json"))
    }

    private static let secondResult = PolishResult(
        polishedText: "Second answer.",
        learningSummary: nil,
        detectedLanguage: "Spanish",
        wasTranslated: true,
        modelUsed: ModelRouting.sonnetModel
    )

    private func makeModel(_ polisher: any Polishing = FakePolisher()) -> AppModel {
        AppModel.testing(polisher: polisher, directory: directory)
    }

    private func process(_ model: AppModel, _ text: String, channel: Channel = .formal) async {
        model.input = NSAttributedString(string: text)
        model.channel = channel
        await model.process()
    }

    private func markdown(_ text: NSAttributedString) -> String {
        RichText.markdown(from: RichTextBridge.attributedString(from: text))
    }

    private func saved() throws -> [HistoryEntry] {
        try store.load()
    }

    @Test func successRecordsAnEntryAndSavesIt() async throws {
        let model = makeModel()

        await process(model, "  I will to review the doc ", channel: .slack)

        let entry = try #require(model.history.first)
        #expect(model.history.count == 1)
        #expect(model.currentHistoryID == entry.id)
        #expect(entry.channel == .slack)
        #expect(entry.inputMarkdown == "I will to review the doc")
        #expect(entry.outputMarkdown == PolishResult.sample.polishedText)
        #expect(entry.learningSummary == PolishResult.sample.learningSummary)
        #expect(entry.detectedLanguage == "English")
        #expect(!entry.wasTranslated)
        #expect(entry.modelUsed == ModelRouting.haikuModel)
        #expect(try saved() == model.history)
    }

    @Test func failureRecordsNothing() async throws {
        let model = makeModel(FakePolisher(outcome: .failure(.claudeNotFound)))

        await process(model, "Hello")

        #expect(model.history.isEmpty)
        #expect(model.currentHistoryID == nil)
        #expect(try saved().isEmpty)
    }

    @Test func cancelRecordsNothing() async throws {
        let polisher = GatedPolisher()
        let model = makeModel(polisher)
        model.input = NSAttributedString(string: "Hello")
        model.startProcessing()
        while polisher.waitingCount < 1 { await Task.yield() }

        model.cancel()
        polisher.resume(0, with: .success(.sample))
        await model.requestTask?.value

        #expect(model.history.isEmpty)
        #expect(try saved().isEmpty)
    }

    @Test func copySavesTheEditedOutput() async throws {
        let model = makeModel()
        await process(model, "Hello")
        model.output = AppModel.editorText(fromMarkdown: "My **edit**")

        await model.copyResult()

        #expect(model.history.first?.outputMarkdown == "My **edit**")
        #expect(try saved().first?.outputMarkdown == "My **edit**")
    }

    @Test func blankOutputIsNotSavedOnCopy() async throws {
        let model = makeModel()
        await process(model, "Hello")
        model.output = NSAttributedString(string: " \n ")

        await model.copyResult()

        #expect(model.history.first?.outputMarkdown == PolishResult.sample.polishedText)
        #expect(try saved().first?.outputMarkdown == PolishResult.sample.polishedText)
    }

    @Test func blankOutputIsNotSavedOnClear() async throws {
        let model = makeModel()
        await process(model, "Hello")
        model.output = NSAttributedString()

        model.clear()

        #expect(try saved().first?.outputMarkdown == PolishResult.sample.polishedText)
        #expect(model.currentHistoryID == nil)
    }

    @Test func refineSavesTheRefinedOutputToTheSameEntry() async throws {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        await process(model, "Hello")
        let entryID = try #require(model.currentHistoryID)
        polisher.outcome = .success(Self.secondResult)

        model.refine(.shorter)
        await model.requestTask?.value

        #expect(model.history.count == 1)
        #expect(model.currentHistoryID == entryID)
        #expect(model.history.first?.outputMarkdown == "Second answer.")
        #expect(try saved().first?.outputMarkdown == "Second answer.")
    }

    @Test func clearSavesTheEditedOutputAndLeavesTheEntry() async throws {
        let model = makeModel()
        await process(model, "Hello")
        model.output = AppModel.editorText(fromMarkdown: "Edited *before* clear")

        model.clear()

        #expect(try saved().first?.outputMarkdown == "Edited *before* clear")
        #expect(model.currentHistoryID == nil)
        #expect(model.history.count == 1)
    }

    @Test func nextRequestSavesTheEditedOutputFirst() async throws {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        await process(model, "First")
        model.output = AppModel.editorText(fromMarkdown: "Edited first")

        polisher.outcome = .success(Self.secondResult)
        await process(model, "Segundo")

        let entries = try saved()
        #expect(entries.count == 2)
        #expect(entries.map(\.outputMarkdown).contains("Edited first"))
        #expect(entries.map(\.outputMarkdown).contains("Second answer."))
        #expect(model.history.first?.outputMarkdown == "Second answer.")
        #expect(model.currentHistoryID == model.history.first?.id)
    }

    @Test func failedNextRequestStillSavesEditsAndLeavesTheEntry() async throws {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        await process(model, "First")
        model.output = AppModel.editorText(fromMarkdown: "Edited first")

        polisher.outcome = .failure(.claudeNotFound)
        await process(model, "Again")
        model.clear()

        #expect(try saved().map(\.outputMarkdown) == ["Edited first"])
        #expect(model.currentHistoryID == nil)
    }

    @Test func restorePutsEverythingBack() async throws {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        await process(model, "I will to review the doc", channel: .slack)
        let first = try #require(model.history.first)
        polisher.outcome = .success(Self.secondResult)
        await process(model, "Segundo", channel: .formal)

        model.restoreHistoryEntry(id: first.id)

        #expect(model.input.string == "I will to review the doc")
        #expect(markdown(model.output) == PolishResult.sample.polishedText)
        #expect(model.result == .sample)
        #expect(model.channel == .slack)
        #expect(model.currentHistoryID == first.id)
        #expect(model.errorMessage == nil)
    }

    @Test func restoreSavesTheCurrentEditsAndBringsBackEditedOutput() async throws {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        await process(model, "First")
        let first = try #require(model.history.first)
        model.output = AppModel.editorText(fromMarkdown: "Edited first")
        polisher.outcome = .success(Self.secondResult)
        await process(model, "Second")
        model.output = AppModel.editorText(fromMarkdown: "Edited second")
        let second = try #require(model.history.first)

        model.restoreHistoryEntry(id: first.id)

        #expect(markdown(model.output) == "Edited first")
        #expect(model.result?.polishedText == "Edited first")
        #expect(try saved().first { $0.id == second.id }?.outputMarkdown == "Edited second")
    }

    /// Processes two texts, then edits the output and makes the history folder read-only, so the
    /// next save fails. Returns the first entry's id.
    private func twoEntriesWithFailingSave(_ model: AppModel, _ polisher: FakePolisher)
        async throws -> UUID
    {
        await process(model, "First")
        let first = try #require(model.history.first)
        polisher.outcome = .success(Self.secondResult)
        await process(model, "Second")
        model.output = AppModel.editorText(fromMarkdown: "Unsaved edit")
        try setPermissions(0o555, of: directory)
        return first.id
    }

    @Test func restoreShowsTheSaveFailureAndStillRestores() async throws {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        let firstID = try await twoEntriesWithFailingSave(model, polisher)
        defer { try? setPermissions(0o755, of: directory) }

        model.restoreHistoryEntry(id: firstID)

        #expect(model.currentHistoryID == firstID)
        #expect(markdown(model.output) == PolishResult.sample.polishedText)
        #expect(model.errorMessage?.contains("Couldn't save the history") == true)
    }

    @Test func restoreOfAMissingEntryStillShowsTheSaveFailure() async throws {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        _ = try await twoEntriesWithFailingSave(model, polisher)
        defer { try? setPermissions(0o755, of: directory) }
        let current = model.currentHistoryID

        model.restoreHistoryEntry(id: UUID())

        #expect(model.currentHistoryID == current)
        #expect(markdown(model.output) == "Unsaved edit")
        #expect(model.errorMessage?.contains("Couldn't save the history") == true)
    }

    @Test func restoreOfAMissingEntryChangesNothing() async throws {
        let model = makeModel()
        await process(model, "Hello")
        let current = model.currentHistoryID

        model.restoreHistoryEntry(id: UUID())

        #expect(model.currentHistoryID == current)
        #expect(model.result == .sample)
        #expect(model.errorMessage == nil)
    }

    @Test func historyIsLoadedAtLaunch() async throws {
        let first = makeModel()
        await process(first, "Hello")

        let relaunched = makeModel()

        #expect(relaunched.history == first.history)
        #expect(relaunched.currentHistoryID == nil)
        #expect(relaunched.errorMessage == nil)
    }

    @Test func deleteRemovesTheEntryAndDetachesTheScreen() async throws {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        await process(model, "First")
        let first = try #require(model.history.first)
        polisher.outcome = .success(Self.secondResult)
        await process(model, "Second")
        let second = try #require(model.history.first)

        model.deleteHistoryEntry(id: second.id)

        #expect(model.history.map(\.id) == [first.id])
        #expect(try saved().map(\.id) == [first.id])
        #expect(model.currentHistoryID == nil)
        #expect(model.output.length > 0)
    }

    @Test func deletingAnotherEntryKeepsTheCurrentOne() async throws {
        let polisher = FakePolisher()
        let model = makeModel(polisher)
        await process(model, "First")
        let first = try #require(model.history.first)
        polisher.outcome = .success(Self.secondResult)
        await process(model, "Second")
        let current = model.currentHistoryID

        model.deleteHistoryEntry(id: first.id)

        #expect(model.currentHistoryID == current)
        #expect(try saved().count == 1)
    }

    @Test func clearHistoryRemovesEverythingButKeepsTheScreen() async throws {
        let model = makeModel()
        await process(model, "First")
        await process(model, "Second")

        model.clearHistory()

        #expect(model.history.isEmpty)
        #expect(model.currentHistoryID == nil)
        #expect(try saved().isEmpty)
        #expect(model.result == .sample)
    }

    @Test func historyKeepsOnlyTheNewestEntriesInMemory() async throws {
        let model = AppModel(
            polisher: FakePolisher(),
            learningLog: LearningLog(fileURL: directory.appending(path: "learning-log.md")),
            historyStore: HistoryStore(fileURL: store.fileURL, limit: 2),
            writeToPasteboard: { _ in },
            sleep: { _ in }
        )

        for text in ["One", "Two", "Three"] {
            await process(model, text)
        }

        #expect(model.history.map(\.inputMarkdown) == ["Three", "Two"])
    }

    @Test func corruptFileShowsBannerAndStartsEmpty() throws {
        try Data("not json".utf8).write(to: store.fileURL)

        let model = makeModel()

        #expect(model.history.isEmpty)
        let expected = HistoryStoreError.corrupted(backup: store.backupURL).errorDescription
        #expect(model.errorMessage == expected)
    }

    @Test func corruptFileBannerSurvivesALaterStartupError() throws {
        try Data("not json".utf8).write(to: store.fileURL)
        let model = makeModel()

        model.showStartupError(PolishError.claudeNotFound)

        let message = try #require(model.errorMessage)
        #expect(message.contains("history file was damaged"))
        #expect(message.contains(PolishError.claudeNotFound.errorDescription ?? "missing"))
    }

    private func setPermissions(_ permissions: Int, of url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private static let notSavedNotice = "New history won't be saved until you relaunch the app"

    @Test func unreadableFileIsNeverOverwritten() async throws {
        let original = Data("[]  ".utf8)
        try original.write(to: store.fileURL)
        try setPermissions(0o000, of: store.fileURL)
        defer { try? setPermissions(0o644, of: store.fileURL) }
        let model = makeModel()
        let startup = try #require(model.errorMessage)
        #expect(startup.contains("Couldn't read the history"))
        #expect(startup.contains(Self.notSavedNotice))

        await process(model, "Hello")
        model.output = AppModel.editorText(fromMarkdown: "Edited")
        await model.copyResult()

        #expect(model.result == .sample)
        #expect(model.history.count == 1)
        try setPermissions(0o644, of: store.fileURL)
        #expect(try Data(contentsOf: store.fileURL) == original)
    }

    @Test func folderInPlaceOfTheFileShowsBannerAndSkipsSaving() async throws {
        try FileManager.default.createDirectory(
            at: store.fileURL, withIntermediateDirectories: true)
        let model = makeModel()
        #expect(model.errorMessage?.contains(Self.notSavedNotice) == true)

        await process(model, "Hello")

        #expect(model.errorMessage == nil)
        #expect(model.history.count == 1)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: store.fileURL.path, isDirectory: &isDirectory)
        #expect(exists && isDirectory.boolValue)
    }

    @Test func damagedFileThatCantBeMovedAsideIsNeverOverwritten() async throws {
        let original = Data("not json".utf8)
        try original.write(to: store.fileURL)
        try setPermissions(0o555, of: directory)
        let model = makeModel()
        try setPermissions(0o755, of: directory)
        let startup = try #require(model.errorMessage)
        #expect(startup.contains("couldn't be moved aside"))
        #expect(startup.contains(Self.notSavedNotice))

        await process(model, "Hello")
        model.clearHistory()

        #expect(try Data(contentsOf: store.fileURL) == original)
        #expect(!FileManager.default.fileExists(atPath: store.backupURL.path))
    }

    @Test func saveFailureShowsBannerAndKeepsResult() async throws {
        let blocker = directory.appending(path: "not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let model = AppModel.testing(polisher: FakePolisher(), directory: blocker)

        await process(model, "Hello")

        #expect(model.result == .sample)
        #expect(model.history.count == 1)
        let message = try #require(model.errorMessage)
        #expect(message.contains("Couldn't save the history"))
    }
}
