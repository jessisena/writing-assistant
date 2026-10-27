import Testing
import WritingAssistantCore

private let haiku = ModelRouting.haikuModel
private let sonnet = ModelRouting.sonnetModel

private func repeated(_ word: String, _ count: Int) -> String {
    Array(repeating: word, count: count).joined(separator: " ")
}

@Suite struct RoutingTests {
    @Test func shortEnglishRoutesToHaiku() {
        #expect(ModelRouting.pickModel(for: "Please send me the report by end of day.") == haiku)
    }

    @Test func shortEnglishQuestionRoutesToHaiku() {
        let text = "Can you review this before our meeting tomorrow?"
        #expect(ModelRouting.pickModel(for: text) == haiku)
    }

    @Test func shortSpanishRoutesToSonnet() {
        let text = "Por favor envíame el informe antes de que termine el día."
        #expect(ModelRouting.pickModel(for: text) == sonnet)
    }

    @Test func shortPortugueseRoutesToSonnet() {
        let text = "Por favor me envie o relatório antes do final do dia."
        #expect(ModelRouting.pickModel(for: text) == sonnet)
    }

    @Test func longEnglishRoutesToSonnet() {
        #expect(ModelRouting.pickModel(for: repeated("hello", 70)) == sonnet)
    }

    @Test func shortASCIIUnknownWordRoutesToHaiku() {
        #expect(ModelRouting.pickModel(for: "Hola") == haiku)
    }

    @Test func emptyStringRoutesToSonnet() {
        #expect(ModelRouting.pickModel(for: "") == sonnet)
    }

    @Test func accentedCharactersRouteToSonnet() {
        #expect(ModelRouting.pickModel(for: "Désolé, je suis en retard.") == sonnet)
    }

    @Test(arguments: [
        ("Hello how are you today", haiku),
        ("El proyecto está listo para revisión", sonnet),
        (repeated("word", 61), sonnet),
    ])
    func parametrizedRouting(text: String, expected: String) {
        #expect(ModelRouting.pickModel(for: text) == expected)
    }

    @Test func exactlySixtyEnglishWordsRoutesToHaiku() {
        #expect(ModelRouting.pickModel(for: repeated("word", 60)) == haiku)
    }

    @Test func oneStopwordHitStillRoutesToHaiku() {
        #expect(ModelRouting.pickModel(for: "Send the report pero today") == haiku)
    }

    @Test func stopwordsWithPunctuationAndCapitalsCount() {
        #expect(ModelRouting.pickModel(for: "\"El\" report, PERO! today") == sonnet)
    }

    @Test func nonASCIIRatioOfExactlyTwoPercentRoutesToHaiku() {
        let text = "é" + String(repeating: "a", count: 49)
        #expect(ModelRouting.pickModel(for: text) == haiku)
    }

    @Test func nonASCIIRatioAboveTwoPercentRoutesToSonnet() {
        let text = "é" + String(repeating: "a", count: 48)
        #expect(ModelRouting.pickModel(for: text) == sonnet)
    }

    @Test func whitespaceOnlyRoutesToHaiku() {
        #expect(ModelRouting.pickModel(for: "   ") == haiku)
    }
}
