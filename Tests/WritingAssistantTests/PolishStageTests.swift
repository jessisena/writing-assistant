import Testing
import WritingAssistantCore

@testable import WritingAssistant

@Suite struct PolishStageTests {
    private static let cases: [(PolishPreview?, Bool, PolishStage)] = [
        (nil, true, .detectingLanguage),
        (PolishPreview(detectedLanguage: "Spanish"), true, .detectingLanguage),
        (
            PolishPreview(detectedLanguage: "Spanish", wasTranslated: true), true,
            .translating(from: "Spanish")
        ),
        (PolishPreview(wasTranslated: true), true, .translating(from: nil)),
        (
            PolishPreview(polishedText: "Ho", detectedLanguage: "Spanish", wasTranslated: true),
            true, .translating(from: "Spanish")
        ),
        (PolishPreview(detectedLanguage: "English", wasTranslated: false), true, .polishing),
        (PolishPreview(polishedText: ""), true, .polishing),
        (PolishPreview(polishedText: "Hi", detectedLanguage: "French"), true, .polishing),
        (PolishPreview(polishedText: "Hi", isTextComplete: true), true, .writingTips),
        (
            PolishPreview(polishedText: "Hi", isTextComplete: true, wasTranslated: false), true,
            .writingTips
        ),
        (
            PolishPreview(polishedText: "Hi", isTextComplete: true, wasTranslated: false), false,
            .finishing
        ),
        (
            PolishPreview(polishedText: "Hi", isTextComplete: true, wasTranslated: true), true,
            .finishing
        ),
    ]

    @Test(arguments: cases)
    func stageFollowsWhatTheReplySaid(
        preview: PolishPreview?, includesSummary: Bool, expected: PolishStage
    ) {
        let options = PolishOptions(
            mode: .work, outputLanguage: .english, includesLearningSummary: includesSummary)
        #expect(PolishStage(preview, options: options) == expected)
    }

    private static let sameAsInputCases: [(PolishPreview, PolishStage)] = [
        (
            PolishPreview(
                polishedText: "Hola", isTextComplete: true, detectedLanguage: "Spanish",
                wasTranslated: false), .finishing
        ),
        (PolishPreview(polishedText: "Hola", isTextComplete: true), .finishing),
        (
            PolishPreview(
                polishedText: "Hi", isTextComplete: true, detectedLanguage: "English",
                wasTranslated: false), .writingTips
        ),
    ]

    @Test(arguments: sameAsInputCases)
    func sameAsInputOnlyWritesTipsForEnglish(preview: PolishPreview, expected: PolishStage) {
        let options = PolishOptions(
            mode: .personal, outputLanguage: .sameAsInput, includesLearningSummary: true)
        #expect(PolishStage(preview, options: options) == expected)
    }

    @Test(arguments: [
        (PolishStage.detectingLanguage, "Detecting language…"),
        (.translating(from: "Spanish"), "Translating from Spanish…"),
        (.translating(from: nil), "Translating…"),
        (.polishing, "Polishing…"),
        (.writingTips, "Writing tips…"),
        (.finishing, "Finishing…"),
    ])
    func labels(stage: PolishStage, label: String) {
        #expect(stage.label == label)
    }
}

@Suite struct PreviewMailboxTests {
    @Test func onlyTheFirstPostSchedulesADeliveryAndTakeGetsTheNewest() {
        let mailbox = PreviewMailbox()

        #expect(mailbox.post(PolishPreview(polishedText: "a")))
        #expect(!mailbox.post(PolishPreview(polishedText: "ab")))
        #expect(mailbox.take() == PolishPreview(polishedText: "ab"))
        #expect(mailbox.take() == nil)
        #expect(mailbox.post(PolishPreview(polishedText: "abc")))
    }
}
