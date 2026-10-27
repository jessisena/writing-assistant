import Testing

@testable import WritingAssistantCore

@Suite struct TextDiffTests {
    private func rebuilt(_ segments: [DiffSegment], keeping kind: DiffSegment.Kind) -> String {
        segments.filter { $0.kind == .same || $0.kind == kind }.map(\.text).joined()
    }

    @Test func identicalTextIsOneSameSegment() {
        #expect(
            TextDiff.words(from: "Hello there, team.", to: "Hello there, team.") == [
                DiffSegment(kind: .same, text: "Hello there, team.")
            ])
    }

    @Test func bothEmptyGivesNoSegments() {
        #expect(TextDiff.words(from: "", to: "").isEmpty)
    }

    @Test func emptyOldMeansEverythingIsAdded() {
        #expect(
            TextDiff.words(from: "", to: "brand new text") == [
                DiffSegment(kind: .added, text: "brand new text")
            ])
    }

    @Test func emptyNewMeansEverythingIsRemoved() {
        #expect(
            TextDiff.words(from: "all of this goes", to: "") == [
                DiffSegment(kind: .removed, text: "all of this goes")
            ])
    }

    @Test func middleReplacementPutsRemovedBeforeAdded() {
        #expect(
            TextDiff.words(from: "the cat sat down", to: "the dog sat down") == [
                DiffSegment(kind: .same, text: "the "),
                DiffSegment(kind: .removed, text: "cat"),
                DiffSegment(kind: .added, text: "dog"),
                DiffSegment(kind: .same, text: " sat down"),
            ])
    }

    @Test func insertedWordsAreMergedIntoOneSegment() {
        #expect(
            TextDiff.words(from: "please review", to: "please take a look and review") == [
                DiffSegment(kind: .same, text: "please "),
                DiffSegment(kind: .added, text: "take a look and "),
                DiffSegment(kind: .same, text: "review"),
            ])
    }

    @Test func whitespaceOnlyChangeIsItsOwnSegment() {
        #expect(
            TextDiff.words(from: "one two", to: "one  two") == [
                DiffSegment(kind: .same, text: "one"),
                DiffSegment(kind: .removed, text: " "),
                DiffSegment(kind: .added, text: "  "),
                DiffSegment(kind: .same, text: "two"),
            ])
    }

    @Test func newlineChangeIsDetected() {
        let segments = TextDiff.words(from: "line one line two", to: "line one\nline two")
        #expect(segments.contains(DiffSegment(kind: .added, text: "\n")))
        #expect(segments.contains(DiffSegment(kind: .removed, text: " ")))
    }

    @Test func emojiAreWholeTokens() {
        #expect(
            TextDiff.words(from: "ship it 👍", to: "ship it 🚀") == [
                DiffSegment(kind: .same, text: "ship it "),
                DiffSegment(kind: .removed, text: "👍"),
                DiffSegment(kind: .added, text: "🚀"),
            ])
    }

    @Test func zwjEmojiAreNeverSplit() {
        #expect(
            TextDiff.words(from: "hi 👨‍👩‍👧 all", to: "hi 👨‍👩‍👦 all") == [
                DiffSegment(kind: .same, text: "hi "),
                DiffSegment(kind: .removed, text: "👨‍👩‍👧"),
                DiffSegment(kind: .added, text: "👨‍👩‍👦"),
                DiffSegment(kind: .same, text: " all"),
            ])
    }

    @Test(arguments: [
        ("", "x"),
        ("a b c", "c b a"),
        ("  leading and trailing  ", "leading\tand trailing"),
        ("I has went to the store yesterday", "I went to the store yesterday."),
        ("🇵🇹 olá mundo", "🇪🇸 hola mundo 🎉"),
    ])
    func segmentsRebuildBothSides(old: String, new: String) {
        let segments = TextDiff.words(from: old, to: new)

        #expect(rebuilt(segments, keeping: .removed) == old)
        #expect(rebuilt(segments, keeping: .added) == new)
        #expect(!segments.contains { $0.text.isEmpty })
        for (first, second) in zip(segments, segments.dropFirst()) {
            #expect(first.kind != second.kind, "adjacent segments of the same kind")
        }
    }
}
