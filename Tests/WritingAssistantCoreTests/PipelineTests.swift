import Foundation
import Testing
import WritingAssistantCore

private actor FakeRunner: ClaudeRunning {
    private let output: Result<String, PolishError>
    private let availability: Result<Void, PolishError>
    private let usage: TokenUsage?
    private let costUSD: Double?
    private let streamed: [String]
    private(set) var calls:
        [(systemPrompt: String, input: String, model: String, timeout: Duration)] = []

    /// - Parameter streamed: Pieces passed to `onText`, in order, before `output` is returned.
    init(
        output: Result<String, PolishError>,
        availability: Result<Void, PolishError> = .success(()),
        usage: TokenUsage? = nil,
        costUSD: Double? = nil,
        streamed: [String] = []
    ) {
        self.output = output
        self.availability = availability
        self.usage = usage
        self.costUSD = costUSD
        self.streamed = streamed
    }

    func run(
        systemPrompt: String, input: String, model: String, timeout: Duration,
        onText: @escaping @Sendable (String) -> Void
    ) async throws(PolishError) -> ClaudeReply {
        calls.append((systemPrompt, input, model, timeout))
        streamed.forEach(onText)
        return ClaudeReply(text: try output.get(), usage: usage, costUSD: costUSD)
    }

    func checkAvailable() async throws(PolishError) {
        try availability.get()
    }
}

private struct StubPromptError: LocalizedError {
    var message = "polish.txt is missing"
    var errorDescription: String? { message }
}

private struct StubPromptStore: PromptStoring {
    var assembled: Result<String, StubPromptError> = .success("SYSTEM PROMPT")
    var refinements: Result<String, StubPromptError> = .success("  REFINE INSTRUCTION \n")

    var directoryURL: URL { URL(filePath: "/nonexistent/prompts") }
    func fileURL(_ file: PromptFile) -> URL { directoryURL.appending(path: file.relativePath) }
    func seedMissingDefaults() throws {}
    func read(_ file: PromptFile) throws -> String {
        if case .refinement(let refinement) = file {
            return try refinements.get().replacingOccurrences(
                of: "REFINE", with: refinement.rawValue.uppercased())
        }
        return try assembled.get()
    }
    func write(_ text: String, to file: PromptFile) throws {}
    func restoreDefault(_ file: PromptFile) throws {}
    func syncDefaults() throws -> Set<PromptFile> { [] }
    func acknowledgeDefault(_ file: PromptFile) throws {}
    func assemble(for channel: Channel) throws -> String { try assembled.get() }
}

private func json(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func summaryObject() -> [String: Any] {
    [
        "corrections": [
            [
                "original": "send me the report pls",
                "corrected": "please send me the report by end of day",
                "why": "Avoid informal abbreviations in written professional communication.",
            ]
        ],
        "grammar_insight": "Spelling out polite words like 'please' signals professionalism.",
        "vocabulary": [
            [
                "term": "by end of day",
                "meaning": "before the working day ends",
                "example": "Please submit your feedback by end of day.",
            ]
        ],
    ]
}

private let englishResponse = json([
    "detected_language": "English",
    "was_translated": false,
    "polished_text": "Please send me the report by end of day.",
    "learning_summary": summaryObject(),
])

/// A valid summary with the given `was_translated` value; `nil` leaves the key out.
private func responseWithSummary(wasTranslated: Any?) -> String {
    var object: [String: Any] = ["polished_text": "Hi", "learning_summary": summaryObject()]
    object["was_translated"] = wasTranslated
    return json(object)
}

private func translatedResponse(_ language: String) -> String {
    json([
        "detected_language": language,
        "was_translated": true,
        "polished_text": "Please send me the report by end of day.",
        "learning_summary": NSNull(),
    ])
}

private let disobedientResponse = json([
    "detected_language": "Spanish",
    "was_translated": true,
    "polished_text": "Please send me the report by end of day.",
    "learning_summary": [
        "corrections": [],
        "grammar_insight": "This summary should be stripped by the server.",
        "vocabulary": [],
    ],
])

private func polish(
    _ text: String = "Send me the report pls",
    responding output: String
) async throws(PolishError) -> PolishResult {
    let service = PolishService(
        runner: FakeRunner(output: .success(output)), prompts: StubPromptStore())
    return try await service.polish(text: text, channel: .slack)
}

private func expectBadFormat(_ output: String) async {
    await #expect {
        _ = try await polish(responding: output)
    } throws: { error in
        guard case .badFormat = error as? PolishError else { return false }
        return true
    }
}

@Suite struct WasTranslatedGateTests {
    @Test(arguments: ["Spanish", "Portuguese", "French"])
    func translatedInputHasNoSummary(language: String) async throws {
        let result = try await polish("some text", responding: translatedResponse(language))
        #expect(result.wasTranslated)
        #expect(result.learningSummary == nil)
        #expect(result.detectedLanguage == language)
    }

    @Test func disobedientModelSummaryIsStripped() async throws {
        let result = try await polish("Texto en español", responding: disobedientResponse)
        #expect(result.wasTranslated)
        #expect(result.learningSummary == nil)
    }

    @Test func englishInputKeepsSummary() async throws {
        let result = try await polish(responding: englishResponse)
        #expect(!result.wasTranslated)
        #expect(result.polishedText == "Please send me the report by end of day.")
        #expect(result.learningSummary?.corrections.first?.original == "send me the report pls")
        #expect(result.learningSummary?.vocabulary.first?.term == "by end of day")
        #expect(result.learningSummary?.grammarInsight.hasPrefix("Spelling out") == true)
    }

    @Test(arguments: [englishResponse, disobedientResponse, translatedResponse("Spanish")])
    func summaryImpliesNotTranslated(output: String) async throws {
        let result = try await polish(responding: output)
        #expect(result.learningSummary == nil || !result.wasTranslated)
    }

    @Test func malformedSummaryOnTranslatedResponseIsIgnored() async throws {
        let output = json(["polished_text": "Hi", "was_translated": true, "learning_summary": 42])
        let result = try await polish(responding: output)
        #expect(result.learningSummary == nil)
    }

    @Test(arguments: [
        responseWithSummary(wasTranslated: true),
        responseWithSummary(wasTranslated: 1),
        responseWithSummary(wasTranslated: -0.5),
        responseWithSummary(wasTranslated: "false"),
        responseWithSummary(wasTranslated: [0]),
        responseWithSummary(wasTranslated: ["a": 0]),
    ])
    func truthyWasTranslatedDropsSummary(output: String) async throws {
        let result = try await polish(responding: output)
        #expect(result.wasTranslated)
        #expect(result.learningSummary == nil)
    }

    @Test(arguments: [
        responseWithSummary(wasTranslated: nil),
        responseWithSummary(wasTranslated: false),
        responseWithSummary(wasTranslated: 0),
        responseWithSummary(wasTranslated: 0.0),
        responseWithSummary(wasTranslated: ""),
        responseWithSummary(wasTranslated: [Any]()),
        responseWithSummary(wasTranslated: [String: Any]()),
        responseWithSummary(wasTranslated: NSNull()),
    ])
    func falsyWasTranslatedKeepsSummary(output: String) async throws {
        let result = try await polish(responding: output)
        #expect(!result.wasTranslated)
        #expect(result.learningSummary != nil)
    }

    @Test(arguments: [
        json(["polished_text": "Hi", "was_translated": false]),
        json(["polished_text": "Hi", "was_translated": false, "learning_summary": NSNull()]),
    ])
    func absentOrNullSummaryIsNil(output: String) async throws {
        let result = try await polish(responding: output)
        #expect(result.learningSummary == nil)
    }
}

@Suite struct JSONExtractionTests {
    @Test func fencedJSON() {
        #expect(
            JSONExtraction.extractJSONText(from: "```json\n{\"key\": \"value\"}\n```")
                == "{\"key\": \"value\"}")
    }

    @Test func fenceWithoutLanguageTag() {
        #expect(JSONExtraction.extractJSONText(from: "```\n{\"a\": 1}\n```") == "{\"a\": 1}")
    }

    @Test func firstFenceWins() {
        let raw = "```json\n{\"a\": 1}\n```\nand\n```json\n{\"b\": 2}\n```"
        #expect(JSONExtraction.extractJSONText(from: raw) == "{\"a\": 1}")
    }

    @Test func plainJSON() {
        #expect(
            JSONExtraction.extractJSONText(from: "  {\"key\": \"value\"}\n")
                == "{\"key\": \"value\"}")
    }

    @Test func preambleBeforeJSON() {
        let raw = "Now I will compile the result:\n\n{\"key\": \"value\"}"
        #expect(JSONExtraction.extractJSONText(from: raw) == "{\"key\": \"value\"}")
    }

    @Test func garbageIsReturnedTrimmed() {
        #expect(JSONExtraction.extractJSONText(from: " not json at all \n") == "not json at all")
    }

    @Test func closingBraceBeforeOpeningIsNotSliced() {
        #expect(JSONExtraction.extractJSONText(from: "} oops {") == "} oops {")
    }

    @Test func fencedResponseParsesThroughService() async throws {
        let output = "Here you go:\n```json\n\(englishResponse)\n```"
        let result = try await polish(responding: output)
        #expect(result.learningSummary != nil)
    }

    @Test func preambleResponseParsesThroughService() async throws {
        let result = try await polish(responding: "Result:\n\n\(englishResponse)\nDone.")
        #expect(result.polishedText == "Please send me the report by end of day.")
    }
}

@Suite struct PipelineErrorTests {
    @Test(arguments: ["this is not json at all", "not json", "[1, 2, 3]", "{\"a\": }"])
    func unparsableResponseIsBadFormat(output: String) async {
        await expectBadFormat(output)
    }

    @Test func missingPolishedTextIsBadFormat() async {
        await expectBadFormat(json(["detected_language": "English", "was_translated": false]))
    }

    @Test func nonStringPolishedTextIsBadFormat() async {
        await expectBadFormat(json(["polished_text": 5, "was_translated": false]))
    }

    @Test(arguments: [
        json(["polished_text": "Hi", "learning_summary": ["corrections": []]]),
        json(["polished_text": "Hi", "learning_summary": "not an object"]),
        json([
            "polished_text": "Hi",
            "learning_summary": [
                "corrections": [["original": "x"]], "grammar_insight": "", "vocabulary": [],
            ],
        ]),
    ])
    func malformedLearningSummaryIsBadFormat(output: String) async {
        await expectBadFormat(output)
    }

    @Test func detectedLanguageDefaultsToUnknown() async throws {
        let result = try await polish(responding: json(["polished_text": "Hi"]))
        #expect(result.detectedLanguage == "Unknown")
    }

    @Test func runnerErrorPropagatesUnchanged() async {
        let service = PolishService(
            runner: FakeRunner(output: .failure(.timeout(seconds: 120))), prompts: StubPromptStore()
        )
        await #expect(throws: PolishError.timeout(seconds: 120)) {
            try await service.polish(text: "Hello", channel: .slack)
        }
    }

    @Test func promptStoreFailureIsPromptUnavailable() async {
        let runner = FakeRunner(output: .success(englishResponse))
        let prompts = StubPromptStore(assembled: .failure(StubPromptError()))
        let service = PolishService(runner: runner, prompts: prompts)
        await #expect(throws: PolishError.promptUnavailable(detail: "polish.txt is missing")) {
            try await service.polish(text: "Hello", channel: .slack)
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test func checkReadyForwardsRunnerAvailability() async throws {
        let ready = PolishService(
            runner: FakeRunner(output: .success("")), prompts: StubPromptStore())
        try await ready.checkReady()

        let missing = PolishService(
            runner: FakeRunner(output: .success(""), availability: .failure(.claudeNotFound)),
            prompts: StubPromptStore())
        await #expect(throws: PolishError.claudeNotFound) {
            try await missing.checkReady()
        }
    }
}

@Suite struct InputBoundsTests {
    private func service(_ runner: FakeRunner) -> PolishService {
        PolishService(runner: runner, prompts: StubPromptStore(), timeout: .seconds(7))
    }

    @Test(arguments: ["", "   ", " \n\t "])
    func emptyOrWhitespaceInputIsRejected(text: String) async {
        let runner = FakeRunner(output: .success(englishResponse))
        await #expect(throws: PolishError.emptyInput) {
            try await service(runner).polish(text: text, channel: .slack)
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test(arguments: [1, PolishService.maxInputLength])
    func inputWithinLimitIsAccepted(length: Int) async throws {
        let runner = FakeRunner(output: .success(englishResponse))
        _ = try await service(runner).polish(
            text: String(repeating: "a", count: length), channel: .slack)
        #expect(await runner.calls.count == 1)
    }

    @Test func inputOverLimitIsRejected() async {
        let runner = FakeRunner(output: .success(englishResponse))
        let text = String(repeating: "a", count: PolishService.maxInputLength + 1)
        await #expect(throws: PolishError.inputTooLong(limit: 20_000)) {
            try await service(runner).polish(text: text, channel: .slack)
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test func lengthIsCountedInUnicodeScalars() async {
        let runner = FakeRunner(output: .success(englishResponse))
        let text = String(repeating: "e\u{301}", count: PolishService.maxInputLength / 2 + 1)
        await #expect(throws: PolishError.inputTooLong(limit: 20_000)) {
            try await service(runner).polish(text: text, channel: .slack)
        }
    }

    @Test func surroundingWhitespaceDoesNotCountTowardsLimit() async throws {
        let runner = FakeRunner(output: .success(englishResponse))
        let text = "  " + String(repeating: "a", count: PolishService.maxInputLength) + "\n"
        _ = try await service(runner).polish(text: text, channel: .slack)
        #expect(await runner.calls.count == 1)
    }

    @Test func runnerReceivesPromptModelAndTimeout() async throws {
        let runner = FakeRunner(output: .success(englishResponse))
        let result = try await service(runner).polish(text: "  Hello there \n", channel: .formal)
        let calls = await runner.calls
        #expect(calls.count == 1)
        #expect(calls.first?.systemPrompt == "SYSTEM PROMPT")
        #expect(calls.first?.input == "Hello there")
        #expect(calls.first?.model == ModelRouting.haikuModel)
        #expect(calls.first?.timeout == .seconds(7))
        #expect(result.modelUsed == ModelRouting.haikuModel)
    }

    @Test func nonEnglishInputUsesSonnet() async throws {
        let runner = FakeRunner(output: .success(translatedResponse("Spanish")))
        let text = "Por favor envíame el informe antes de que termine el día."
        let result = try await service(runner).polish(text: text, channel: .slack)
        #expect(await runner.calls.first?.model == ModelRouting.sonnetModel)
        #expect(result.modelUsed == ModelRouting.sonnetModel)
    }
}

@Suite struct RefinePipelineTests {
    private let refinedResponse = json([
        "detected_language": "English",
        "was_translated": false,
        "polished_text": "Send the report today.",
        "learning_summary": summaryObject(),
    ])

    private func service(
        _ runner: FakeRunner, prompts: StubPromptStore = StubPromptStore()
    ) -> PolishService {
        PolishService(runner: runner, prompts: prompts, timeout: .seconds(9))
    }

    @Test(arguments: Refinement.allCases)
    func systemPromptAppendsTheRefinementInstruction(refinement: Refinement) async throws {
        let runner = FakeRunner(output: .success(refinedResponse))
        _ = try await service(runner).refine(
            text: "  Please send me the report.\n", channel: .formal, refinement: refinement)

        let call = try #require(await runner.calls.first)
        let instruction = "\(refinement.rawValue.uppercased()) INSTRUCTION"
        let prompt = call.systemPrompt
        #expect(prompt.hasPrefix("SYSTEM PROMPT\n\n## Additional instruction\n\n\(instruction)\n"))
        #expect(prompt.contains("already-polished English"))
        #expect(prompt.hasSuffix("learning_summary to null."))
        #expect(call.input == "Please send me the report.")
    }

    @Test func returnsOnlyThePolishedText() async throws {
        let runner = FakeRunner(output: .success(refinedResponse))
        let refined = try await service(runner).refine(
            text: "Please send me the report.", channel: .slack, refinement: .shorter)
        #expect(refined == "Send the report today.")
    }

    @Test func runnerReceivesRoutedModelAndTimeout() async throws {
        let runner = FakeRunner(output: .success(refinedResponse))
        _ = try await service(runner).refine(text: "Hi", channel: .slack, refinement: .shorter)
        let long = String(repeating: "word ", count: 100)
        _ = try await service(runner).refine(text: long, channel: .slack, refinement: .shorter)

        let calls = await runner.calls
        #expect(calls.map(\.model) == [ModelRouting.haikuModel, ModelRouting.sonnetModel])
        #expect(calls.allSatisfy { $0.timeout == .seconds(9) })
    }

    @Test(arguments: ["", " \n\t "])
    func emptyInputIsRejected(text: String) async {
        let runner = FakeRunner(output: .success(refinedResponse))
        await #expect(throws: PolishError.emptyInput) {
            try await service(runner).refine(text: text, channel: .slack, refinement: .shorter)
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test func inputOverLimitIsRejected() async {
        let runner = FakeRunner(output: .success(refinedResponse))
        let text = String(repeating: "a", count: PolishService.maxInputLength + 1)
        await #expect(throws: PolishError.inputTooLong(limit: PolishService.maxInputLength)) {
            try await service(runner).refine(text: text, channel: .slack, refinement: .moreFormal)
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test func missingRefinementFileIsPromptUnavailable() async {
        let runner = FakeRunner(output: .success(refinedResponse))
        let missing = StubPromptError(message: "shorter.txt is missing")
        let prompts = StubPromptStore(refinements: .failure(missing))
        await #expect(throws: PolishError.promptUnavailable(detail: "shorter.txt is missing")) {
            try await service(runner, prompts: prompts).refine(
                text: "Hello", channel: .slack, refinement: .shorter)
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test func missingChannelPromptIsPromptUnavailable() async {
        let runner = FakeRunner(output: .success(refinedResponse))
        let prompts = StubPromptStore(assembled: .failure(StubPromptError()))
        await #expect(throws: PolishError.promptUnavailable(detail: "polish.txt is missing")) {
            try await service(runner, prompts: prompts).refine(
                text: "Hello", channel: .slack, refinement: .moreCasual)
        }
        #expect(await runner.calls.isEmpty)
    }

    @Test(arguments: [
        "not json", "[1]", json(["was_translated": false]), json(["polished_text": 3]),
    ])
    func unusableResponseIsBadFormat(output: String) async {
        let runner = FakeRunner(output: .success(output))
        await #expect {
            _ = try await service(runner).refine(
                text: "Hello", channel: .slack, refinement: .moreCasual)
        } throws: { error in
            guard case .badFormat = error as? PolishError else { return false }
            return true
        }
    }

    @Test func runnerErrorPropagatesUnchanged() async {
        let runner = FakeRunner(output: .failure(.cliFailed(stderr: "boom")))
        await #expect(throws: PolishError.cliFailed(stderr: "boom")) {
            try await service(runner).refine(text: "Hello", channel: .slack, refinement: .shorter)
        }
    }

    @Test(arguments: [
        json(["polished_text": "Hey there", "learning_summary": [String: Any]()]),
        json(["polished_text": "Hey there", "learning_summary": 42]),
        json(["polished_text": "Hey there", "learning_summary": "notes"]),
        json(["polished_text": "Hey there", "was_translated": "yes"]),
        json(["polished_text": "Hey there"]),
    ])
    func learningSummaryAndOtherFieldsAreIgnored(output: String) async throws {
        let runner = FakeRunner(output: .success(output))
        let refined = try await service(runner).refine(
            text: "Hello", channel: .slack, refinement: .moreCasual)
        #expect(refined == "Hey there")
    }
}

@Suite struct LearningSummaryToggleTests {
    @Test func turnedOffAddsTheNoteAndDropsAnySummary() async throws {
        let runner = FakeRunner(output: .success(englishResponse))
        let service = PolishService(runner: runner, prompts: StubPromptStore())

        let result = try await service.polish(
            text: "Hello there", channel: .slack, includeLearningSummary: false,
            onPreview: { _ in })

        #expect(result.learningSummary == nil)
        #expect(result.polishedText == "Please send me the report by end of day.")
        #expect(
            await runner.calls.first?.systemPrompt
                == "SYSTEM PROMPT\n\n\(PolishService.summaryOffNote)")
    }

    @Test func turnedOnKeepsThePromptAndTheSummary() async throws {
        let runner = FakeRunner(output: .success(englishResponse))
        let service = PolishService(runner: runner, prompts: StubPromptStore())

        let result = try await service.polish(
            text: "Hello there", channel: .slack, includeLearningSummary: true,
            onPreview: { _ in })

        #expect(result.learningSummary != nil)
        #expect(await runner.calls.first?.systemPrompt == "SYSTEM PROMPT")
    }
}

/// What happened during a polish call, in order: each preview, then the return.
private final class PreviewLog: @unchecked Sendable {
    enum Event: Equatable {
        case preview(PolishPreview)
        case returned
    }

    private let lock = NSLock()
    private var _events: [Event] = []

    var events: [Event] { lock.withLock { _events } }

    func record(_ event: Event) {
        lock.withLock { _events.append(event) }
    }
}

@Suite struct PolishPreviewTests {
    /// `text` cut into pieces of `size` characters, the way a reply streams in.
    private func pieces(of text: String, size: Int) -> [String] {
        stride(from: 0, to: text.count, by: size).map { start in
            let from = text.index(text.startIndex, offsetBy: start)
            let to = text.index(from, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            return String(text[from..<to])
        }
    }

    private func polish(streaming streamed: [String], reply: String, log: PreviewLog)
        async throws(PolishError) -> PolishResult
    {
        let runner = FakeRunner(output: .success(reply), streamed: streamed)
        let service = PolishService(runner: runner, prompts: StubPromptStore())
        let result = try await service.polish(
            text: "Hello", channel: .slack, includeLearningSummary: true,
            onPreview: { log.record(.preview($0)) })
        log.record(.returned)
        return result
    }

    @Test(arguments: [1, 7, 1_000])
    func previewIsSentOnceBeforeTheResult(pieceSize: Int) async throws {
        let reply = "```json\n\(englishResponse)\n```"
        let log = PreviewLog()

        let result = try await polish(
            streaming: pieces(of: reply, size: pieceSize), reply: reply, log: log)

        let preview = PolishPreview(
            polishedText: "Please send me the report by end of day.", detectedLanguage: "English",
            wasTranslated: nil)
        #expect(log.events == [.preview(preview), .returned])
        #expect(result.polishedText == preview.polishedText)
        #expect(result.learningSummary != nil)
    }

    @Test func replyThatNeverClosesThePolishedTextSendsNoPreview() async throws {
        let log = PreviewLog()

        let result = try await polish(
            streaming: [#"{"polished_text": "Please send"#, " me the report"],
            reply: englishResponse, log: log)

        #expect(log.events == [.returned])
        #expect(result.polishedText == "Please send me the report by end of day.")
    }

    @Test func finalReplyIsStillParsedOnItsOwnAfterAPreview() async {
        let log = PreviewLog()

        await #expect {
            _ = try await polish(
                streaming: [#"{"polished_text": "Hi", "#], reply: "not json", log: log)
        } throws: { error in
            guard case .badFormat = error as? PolishError else { return false }
            return true
        }
        #expect(
            log.events == [
                .preview(
                    PolishPreview(polishedText: "Hi", detectedLanguage: nil, wasTranslated: nil))
            ])
    }
}

private final class RecordingUsage: UsageRecording, @unchecked Sendable {
    struct Entry: Equatable {
        let tokens: TokenUsage
        let costUSD: Double?
    }

    private let lock = NSLock()
    private var _recorded: [Entry] = []
    private let failure: (any Error)?

    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    var recorded: [Entry] { lock.withLock { _recorded } }

    func record(_ usage: TokenUsage, costUSD: Double?) throws {
        if let failure { throw failure }
        lock.withLock { _recorded.append(Entry(tokens: usage, costUSD: costUSD)) }
    }
}

@Suite struct UsageRecordingTests {
    private let tokens = TokenUsage(input: 3, output: 40, cacheCreation: 100, cacheRead: 2_000)
    private var priced: RecordingUsage.Entry { .init(tokens: tokens, costUSD: 0.25) }

    private func service(
        responding output: String, usage reported: TokenUsage?, costUSD: Double? = 0.25,
        into usage: RecordingUsage
    ) -> PolishService {
        PolishService(
            runner: FakeRunner(output: .success(output), usage: reported, costUSD: costUSD),
            prompts: StubPromptStore(), usage: usage)
    }

    @Test func polishAndRefineRecordTheReplyTokensAndCost() async throws {
        let usage = RecordingUsage()
        let service = service(responding: englishResponse, usage: tokens, into: usage)

        _ = try await service.polish(text: "Hello", channel: .slack)
        _ = try await service.refine(text: "Hello", channel: .slack, refinement: .shorter)

        #expect(usage.recorded == [priced, priced])
    }

    @Test func replyWithoutCostStillRecordsItsTokens() async throws {
        let usage = RecordingUsage()
        let service = service(
            responding: englishResponse, usage: tokens, costUSD: nil, into: usage)

        _ = try await service.polish(text: "Hello", channel: .slack)

        #expect(usage.recorded == [RecordingUsage.Entry(tokens: tokens, costUSD: nil)])
    }

    @Test func replyThatFailsToParseIsStillRecorded() async {
        let usage = RecordingUsage()
        let service = service(responding: "not json", usage: tokens, into: usage)

        await #expect {
            _ = try await service.polish(text: "Hello", channel: .slack)
        } throws: { error in
            guard case .badFormat = error as? PolishError else { return false }
            return true
        }
        #expect(usage.recorded == [priced])
    }

    @Test func replyWithoutUsageRecordsNothing() async throws {
        let usage = RecordingUsage()
        let service = service(responding: englishResponse, usage: nil, into: usage)

        _ = try await service.polish(text: "Hello", channel: .slack)

        #expect(usage.recorded.isEmpty)
    }

    @Test func recordingFailureDoesNotFailTheRequest() async throws {
        let usage = RecordingUsage(failure: CocoaError(.fileWriteNoPermission))
        let service = service(responding: englishResponse, usage: tokens, into: usage)

        let result = try await service.polish(text: "Hello", channel: .slack)

        #expect(result.polishedText == "Please send me the report by end of day.")
    }
}
