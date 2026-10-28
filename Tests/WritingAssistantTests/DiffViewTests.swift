import AppKit
import SwiftUI
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@Suite struct DiffDisplayTests {
    private let replacement = [
        DiffSegment(kind: .same, text: "I "),
        DiffSegment(kind: .removed, text: "will to review"),
        DiffSegment(kind: .added, text: "'ll review"),
        DiffSegment(kind: .same, text: " the doc 👍"),
    ]

    @Test func textKeepsEverySegmentInOrder() {
        let text = DiffDisplay.attributedText(replacement)

        #expect(String(text.characters) == "I will to review'll review the doc 👍")
    }

    @Test func removedTextIsRedAndStruckThrough() throws {
        let text = DiffDisplay.attributedText(replacement)

        let removed = try #require(text.range(of: "will to review"))
        let run = try #require(text[removed].runs.first)
        #expect(run.foregroundColor == DiffDisplay.removedColor)
        #expect(run.strikethroughStyle == .single)
        #expect(text[removed].runs.count == 1)
    }

    @Test func addedTextIsGreenWithoutStrikethrough() throws {
        let text = DiffDisplay.attributedText(replacement)

        let added = try #require(text.range(of: "'ll review"))
        let run = try #require(text[added].runs.first)
        #expect(run.foregroundColor == DiffDisplay.addedColor)
        #expect(run.strikethroughStyle == nil)
    }

    @Test func unchangedTextHasNoStyling() throws {
        let text = DiffDisplay.attributedText(replacement)

        let same = try #require(text.range(of: " the doc 👍"))
        let run = try #require(text[same].runs.first)
        #expect(run.foregroundColor == nil)
        #expect(run.strikethroughStyle == nil)
    }

    @Test func accessibilityTextNamesRemovedAndAddedParts() {
        #expect(
            DiffDisplay.accessibilityText(replacement)
                == "I, removed: will to review, added: 'll review, the doc 👍")
    }

    @Test func accessibilityTextDescribesWhitespaceOnlyChanges() {
        let segments = [
            DiffSegment(kind: .same, text: "one"),
            DiffSegment(kind: .removed, text: "  "),
            DiffSegment(kind: .added, text: "\n"),
            DiffSegment(kind: .same, text: "two"),
        ]

        #expect(
            DiffDisplay.accessibilityText(segments)
                == "one, removed: whitespace, added: whitespace, two")
    }

    @Test func noSegmentsGiveEmptyTextAndNoChangesDescription() {
        #expect(DiffDisplay.attributedText([]).characters.isEmpty)
        #expect(DiffDisplay.accessibilityText([]) == "No changes")
    }

    @Test func unchangedTextIsDescribedAsNoChanges() {
        let segments = [DiffSegment(kind: .same, text: "Same text")]

        #expect(DiffDisplay.accessibilityText(segments) == "No changes: Same text")
    }

    @MainActor
    @Test func diffComparesPlainTextOfInputAndOutput() {
        let input = AppModel.editorText(fromMarkdown: "Hello **world**")
        let output = AppModel.editorText(fromMarkdown: "Hello *there*")

        #expect(
            DiffDisplay.segments(input: input, output: output) == [
                DiffSegment(kind: .same, text: "Hello "),
                DiffSegment(kind: .removed, text: "world"),
                DiffSegment(kind: .added, text: "there"),
            ])
    }
}

@MainActor
@Suite struct AppModelShowChangesTests {
    private func polishedModel() async -> AppModel {
        let model = AppModel.testing(polisher: FakePolisher())
        model.input = NSAttributedString(string: "I will to review the doc")
        await model.process()
        return model
    }

    @Test func showChangesStartsOff() {
        let model = AppModel.testing(polisher: FakePolisher())
        #expect(!model.showsChanges)
    }

    @Test func showChangesResetsWhenANewResultArrives() async {
        let model = await polishedModel()
        model.showsChanges = true

        await model.process()

        #expect(model.result == .sample)
        #expect(!model.showsChanges)
    }

    @Test func showChangesSurvivesARefinement() async {
        let model = await polishedModel()
        model.showsChanges = true

        model.refine(.shorter)
        await model.requests.task?.value

        #expect(model.showsChanges)
    }

    @Test func clearResetsShowChanges() async {
        let model = await polishedModel()
        model.showsChanges = true

        model.clear(undoManager: nil)

        #expect(!model.showsChanges)
    }
}
