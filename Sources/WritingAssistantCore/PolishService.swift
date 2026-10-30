import Foundation
import os

/// Runs the polish pipeline: validate input, assemble the prompt, call Claude, parse the reply.
public struct PolishService: Polishing {
    public static let maxInputLength = 20_000
    public static let defaultTimeout: Duration = .seconds(120)

    private static let logger = Logger(subsystem: "local.writing-assistant", category: "pipeline")

    private let runner: any ClaudeRunning
    private let prompts: any PromptStoring
    private let usage: (any UsageRecording)?
    private let timeout: Duration

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - runner: Executes prompts against the claude CLI.
    ///   - prompts: Supplies the assembled system prompt for each channel.
    ///   - usage: Gets the tokens of every reply, including replies that then fail to parse.
    ///   - timeout: Upper bound for a single Claude call.
    public init(
        runner: any ClaudeRunning,
        prompts: any PromptStoring,
        usage: (any UsageRecording)? = nil,
        timeout: Duration = PolishService.defaultTimeout
    ) {
        self.runner = runner
        self.prompts = prompts
        self.usage = usage
        self.timeout = timeout
    }

    /// Polishes (or translates, then polishes) `text` for `channel`.
    ///
    /// The result only carries a learning summary when
    /// `options.allowsLearningSummary(detectedLanguage:wasTranslated:)` holds for the reply:
    /// never for a translation, for non-English input or with the summary off, whatever the
    /// model returned.
    ///
    /// - Parameters:
    ///   - text: The user's input. Leading and trailing whitespace is ignored.
    ///   - channel: Selects the channel guidelines inserted into the prompt.
    ///   - options: Select the mode tone and language policy inserted into the prompt; a false
    ///     `includesLearningSummary` leaves the learning summary section out.
    ///   - onPreview: Gets what the reply has said so far after every streamed piece that
    ///     changes it (see `PolishedTextScanner`), in order, on whichever thread the runner
    ///     streams on. The returned result is parsed from the full reply on its own, so it can
    ///     still fail after a complete text was previewed.
    /// - Returns: The parsed result, including the model that produced it.
    /// - Throws: `.emptyInput`, `.inputTooLong`, `.promptUnavailable`, `.badFormat`, or any
    ///   error thrown by the runner, unchanged.
    public func polish(
        text: String, channel: Channel, options: PolishOptions,
        onPreview: @escaping @Sendable (PolishPreview) -> Void
    ) async throws(PolishError) -> PolishResult {
        let input = try Self.validatedInput(text)
        let systemPrompt = try loadPrompt(named: channel.rawValue) {
            try prompts.assemble(for: channel, options: options)
        }
        let scanner = OSAllocatedUnfairLock(initialState: PolishedTextScanner())
        let (raw, model) = try await send(systemPrompt, input: input) { chunk in
            if let preview = scanner.withLock({ $0.feed(chunk) }) {
                onPreview(preview)
            }
        }
        return try Self.parse(raw, model: model, options: options)
    }

    /// Rewrites already-polished `text` for `channel`, following one refinement instruction.
    ///
    /// The prompt is `refine.txt` with the shared rules, the channel guidelines and the
    /// instruction: a preset's refinement file or the user's own text. Only `polished_text` is
    /// read from the reply; any other key the model adds is ignored, even when malformed.
    ///
    /// - Parameters:
    ///   - text: The current polished text. Leading and trailing whitespace is ignored.
    ///   - channel: Selects the channel guidelines inserted into the prompt.
    ///   - refinement: The instruction inserted into the prompt. A custom one is checked with
    ///     `RefinementInstruction.validated()` before anything else.
    /// - Returns: The refined text.
    /// - Throws: `.emptyInstruction`, `.instructionTooLong`, `.emptyInput`, `.inputTooLong`,
    ///   `.promptUnavailable`, `.badFormat`, or any error thrown by the runner, unchanged.
    public func refine(
        text: String, channel: Channel, refinement: RefinementInstruction
    ) async throws(PolishError) -> String {
        let instruction = try refinement.validated()
        let input = try Self.validatedInput(text)
        let systemPrompt = try loadPrompt(named: instruction.logName) {
            try prompts.assembleRefinement(instruction, for: channel)
        }
        let (raw, _) = try await send(systemPrompt, input: input)
        return try Self.polishedText(in: Self.decodeObject(raw))
    }

    /// Wraps `text` in `<draft>` tags so the model treats it as material, not instructions.
    ///
    /// A closing `</draft` inside the text gets a backslash (`<\/draft`), in any letter case, so
    /// the author's text can't end the draft early.
    static func wrapDraft(_ text: String) -> String {
        let neutralized = text.replacingOccurrences(
            of: "</(draft)", with: #"<\\/$1"#, options: [.regularExpression, .caseInsensitive])
        return "<draft>\n\(neutralized)\n</draft>"
    }

    public func checkReady() async throws(PolishError) {
        try await runner.checkAvailable()
    }

    private static func validatedInput(_ text: String) throws(PolishError) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw .emptyInput
        }
        if trimmed.unicodeScalars.count > maxInputLength {
            throw .inputTooLong(limit: maxInputLength)
        }
        return trimmed
    }

    /// Runs `input`, wrapped in `<draft>` tags, under `systemPrompt` on the model routed for the
    /// unwrapped input, returning the raw reply and the model used. The reply's tokens are
    /// recorded; a recording failure is logged and doesn't fail the request.
    private func send(
        _ systemPrompt: String, input: String,
        onText: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws(PolishError) -> (raw: String, model: String) {
        let model = ModelRouting.pickModel(for: input)
        let reply = try await runner.run(
            systemPrompt: systemPrompt, input: Self.wrapDraft(input), model: model,
            timeout: timeout, onText: onText)
        record(reply.usage, costUSD: reply.costUSD)
        return (reply.text, model)
    }

    private func record(_ tokens: TokenUsage?, costUSD: Double?) {
        guard let usage, let tokens else { return }
        do {
            try usage.record(tokens, costUSD: costUSD)
        } catch {
            Self.logger.error(
                "Couldn't record usage: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadPrompt(
        named name: String, _ body: () throws -> String
    ) throws(PolishError) -> String {
        do {
            return try body()
        } catch {
            let detail = error.localizedDescription
            Self.logger.error(
                "Prompt unavailable for \(name, privacy: .public): \(detail, privacy: .public)")
            throw .promptUnavailable(detail: detail)
        }
    }

    /// Reads the reply. `learning_summary` is only decoded when `options` allow a summary for the
    /// reply's language fields; otherwise it is ignored, even when malformed.
    private static func parse(
        _ raw: String, model: String, options: PolishOptions
    ) throws(PolishError) -> PolishResult {
        let object = try decodeObject(raw)
        let polishedText = try polishedText(in: object)
        let wasTranslated = isTruthy(object["was_translated"])
        let language = object["detected_language"] as? String ?? "Unknown"
        let allowsSummary = options.allowsLearningSummary(
            detectedLanguage: language, wasTranslated: wasTranslated)
        let summary = allowsSummary ? try decodeSummary(object["learning_summary"]) : nil
        return PolishResult(
            polishedText: polishedText,
            learningSummary: summary,
            detectedLanguage: language,
            wasTranslated: wasTranslated,
            modelUsed: model
        )
    }

    private static func polishedText(in object: [String: Any]) throws(PolishError) -> String {
        guard let polishedText = object["polished_text"] as? String else {
            throw badFormat("missing or non-string polished_text")
        }
        return polishedText
    }

    private static func decodeObject(_ raw: String) throws(PolishError) -> [String: Any] {
        let text = JSONExtraction.extractJSONText(from: raw)
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
        } catch {
            throw badFormat("response is not valid JSON: \(error.localizedDescription)")
        }
        guard let object = parsed as? [String: Any] else {
            throw badFormat("response JSON is not an object")
        }
        return object
    }

    private static func decodeSummary(_ value: Any?) throws(PolishError) -> LearningSummary? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let object = value as? [String: Any] else {
            throw badFormat("learning_summary is not an object")
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(LearningSummary.self, from: data)
        } catch {
            throw badFormat("invalid learning_summary: \(error)")
        }
    }

    /// Mirrors Python's `bool()` so any truthy `was_translated` drops the summary.
    private static func isTruthy(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            return number.doubleValue != 0
        case let string as String:
            return !string.isEmpty
        case let array as [Any]:
            return !array.isEmpty
        case let object as [String: Any]:
            return !object.isEmpty
        default:
            return false
        }
    }

    private static func badFormat(_ detail: String) -> PolishError {
        logger.error("Bad response format: \(detail, privacy: .public)")
        return .badFormat(detail: detail)
    }
}
