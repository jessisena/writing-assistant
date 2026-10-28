import AppKit
import SwiftUI
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@Suite struct DiffDisplayTests {
    private let palette = ThemePreset.lagoon.palette
    private let replacement = [
        DiffSegment(kind: .same, text: "I "),
        DiffSegment(kind: .removed, text: "will to review"),
        DiffSegment(kind: .added, text: "'ll review"),
        DiffSegment(kind: .same, text: " the doc 👍"),
    ]

    @Test func textKeepsEverySegmentInOrder() {
        let text = DiffDisplay.attributedText(replacement, palette: palette)

        #expect(String(text.characters) == "I will to review'll review the doc 👍")
    }

    @MainActor
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func removedTextIsRedPencilStruckThroughOnATint(appearance: NSAppearance.Name) throws {
        let text = DiffDisplay.attributedText(replacement, palette: palette)

        let removed = try #require(text.range(of: "will to review"))
        let run = try #require(text[removed].runs.first)
        let foreground = try #require(run.foregroundColor)
        let background = try #require(run.backgroundColor)
        #expect(foreground.hex(in: appearance) == palette.redPencil.hex(in: appearance))
        #expect(background.hex(in: appearance) == palette.redPencil.hex(in: appearance))
        #expect(isAlpha(of: background, in: appearance, about: 0.12))
        #expect(run.strikethroughStyle == .single)
        #expect(run.underlineStyle == nil)
        #expect(text[removed].runs.count == 1)
    }

    @MainActor
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func addedTextIsMarginGreenUnderlinedOnATint(appearance: NSAppearance.Name) throws {
        let text = DiffDisplay.attributedText(replacement, palette: palette)

        let added = try #require(text.range(of: "'ll review"))
        let run = try #require(text[added].runs.first)
        let foreground = try #require(run.foregroundColor)
        let background = try #require(run.backgroundColor)
        #expect(foreground.hex(in: appearance) == palette.marginGreen.hex(in: appearance))
        #expect(background.hex(in: appearance) == palette.marginGreen.hex(in: appearance))
        #expect(isAlpha(of: background, in: appearance, about: 0.14))
        #expect(run.underlineStyle == .single)
        #expect(run.strikethroughStyle == nil)
    }

    @MainActor
    private func isAlpha(
        of color: Color, in appearance: NSAppearance.Name, about expected: CGFloat
    ) -> Bool {
        guard let alpha = color.resolved(in: appearance)?.alphaComponent else { return false }
        return abs(alpha - expected) < 0.001
    }

    @Test func unchangedTextHasNoStyling() throws {
        let text = DiffDisplay.attributedText(replacement, palette: palette)

        let same = try #require(text.range(of: " the doc 👍"))
        let run = try #require(text[same].runs.first)
        #expect(run.foregroundColor == nil)
        #expect(run.backgroundColor == nil)
        #expect(run.strikethroughStyle == nil)
        #expect(run.underlineStyle == nil)
    }

    @Test func changeSummaryNamesZeroOneAndManyChanges() {
        #expect(DiffDisplay.changeSummary(0) == "No changes")
        #expect(DiffDisplay.changeSummary(1) == "1 change")
        #expect(DiffDisplay.changeSummary(6) == "6 changes")
    }

    @Test func lineSpacingMatchesTheEditorsLineHeight() {
        let editorLine = RichTextBridge.bodyFontSize * RichTextBridge.lineHeightMultiple
        #expect(abs(RichTextBridge.bodyFontSize + DiffDisplay.lineSpacing - editorLine) < 0.001)
    }

    @Test func noSegmentsHaveNoChanges() {
        #expect(DiffDisplay.changeCount([]) == 0)
    }

    @Test func unchangedTextHasNoChanges() {
        #expect(DiffDisplay.changeCount([DiffSegment(kind: .same, text: "Same text")]) == 0)
    }

    @Test func removedTextFollowedByAddedTextIsOneChange() {
        #expect(DiffDisplay.changeCount(replacement) == 1)
    }

    @Test func aLoneRemovalOrAdditionIsOneChange() {
        #expect(DiffDisplay.changeCount([DiffSegment(kind: .removed, text: "um ")]) == 1)
        #expect(DiffDisplay.changeCount([DiffSegment(kind: .added, text: "so ")]) == 1)
    }

    @Test func changesSeparatedByUnchangedWordsAreCountedSeparately() {
        let segments = [
            DiffSegment(kind: .removed, text: "will"),
            DiffSegment(kind: .added, text: "would"),
            DiffSegment(kind: .same, text: " review the doc "),
            DiffSegment(kind: .removed, text: "tomorrow"),
        ]

        #expect(DiffDisplay.changeCount(segments) == 2)
    }

    @Test func changesSeparatedOnlyByWhitespaceAreOneChange() {
        let segments = [
            DiffSegment(kind: .removed, text: "very"),
            DiffSegment(kind: .same, text: " \n"),
            DiffSegment(kind: .added, text: "really"),
            DiffSegment(kind: .same, text: " "),
            DiffSegment(kind: .removed, text: "good"),
        ]

        #expect(DiffDisplay.changeCount(segments) == 1)
    }

    @Test func aWhitespaceOnlyChangeCountsAsAChange() {
        let segments = [
            DiffSegment(kind: .same, text: "one"),
            DiffSegment(kind: .removed, text: "  "),
            DiffSegment(kind: .added, text: "\n"),
            DiffSegment(kind: .same, text: "two"),
        ]

        #expect(DiffDisplay.changeCount(segments) == 1)
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
        #expect(DiffDisplay.attributedText([], palette: palette).characters.isEmpty)
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
