import Foundation
import os

/// Runs the polish pipeline: validate input, assemble the prompt, call Claude, parse the reply.
public struct PolishService: Polishing {
    public static let maxInputLength = 20_000
    public static let defaultTimeout: Duration = .seconds(120)

    private static let logger = Logger(subsystem: "local.writing-assistant", category: "pipeline")
    private static let refinementNote =
        "The input is already-polished English: apply the additional instruction on top of the "
        + "rules above. Where it conflicts with them (for example a minimal-edit, length or "
        + "formatting rule), the additional instruction wins. Set was_translated to false and set "
        + "learning_summary to null."
    public static let summaryOffNote =
        "The learning summary is turned off: skip Step 4 and set learning_summary to null."

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
    /// When the model reports `was_translated: true`, or `includeLearningSummary` is false, the
    /// result never carries a learning summary, whatever the model returned.
    ///
    /// - Parameters:
    ///   - text: The user's input. Leading and trailing whitespace is ignored.
    ///   - channel: Selects the channel guidelines inserted into the prompt.
    ///   - includeLearningSummary: False tells the model to skip the summary.
    ///   - onPreview: Gets the polished text once it is complete, before the summary, at most
    ///     once and on whichever thread the runner streams on. The returned result is parsed
    ///     from the full reply on its own, so it can still fail after a preview was sent.
    /// - Returns: The parsed result, including the model that produced it.
    /// - Throws: `.emptyInput`, `.inputTooLong`, `.promptUnavailable`, `.badFormat`, or any
    ///   error thrown by the runner, unchanged.
    public func polish(
        text: String, channel: Channel, includeLearningSummary: Bool,
        onPreview: @escaping @Sendable (PolishPreview) -> Void
    ) async throws(PolishError) -> PolishResult {
        let input = try Self.validatedInput(text)
        var systemPrompt = try assemblePrompt(for: channel)
        if !includeLearningSummary {
            systemPrompt += "\n\n\(Self.summaryOffNote)"
        }
        let scanner = OSAllocatedUnfairLock(initialState: PolishedTextScanner())
        let (raw, model) = try await send(systemPrompt, input: input) { chunk in
            if let preview = scanner.withLock({ $0.feed(chunk) }) {
                onPreview(preview)
            }
        }
        var result = try Self.parse(raw, model: model)
        if !includeLearningSummary {
            result.learningSummary = nil
        }
        return result
    }

    /// Rewrites already-polished `text` for `channel`, following one refinement instruction.
    ///
    /// The prompt is the channel's assembled system prompt plus an "Additional instruction"
    /// section holding the refinement file. Only `polished_text` is read from the reply: the
    /// model's language and learning summary describe its own output, so they are ignored, even
    /// when malformed.
    ///
    /// - Parameters:
    ///   - text: The current polished text. Leading and trailing whitespace is ignored.
    ///   - channel: Selects the channel guidelines inserted into the prompt.
    ///   - refinement: Selects the instruction file appended to the prompt.
    /// - Returns: The refined text.
    /// - Throws: `.emptyInput`, `.inputTooLong`, `.promptUnavailable`, `.badFormat`, or any
    ///   error thrown by the runner, unchanged.
    public func refine(
        text: String, channel: Channel, refinement: Refinement
    ) async throws(PolishError) -> String {
        let input = try Self.validatedInput(text)
        let systemPrompt = try assemblePrompt(for: channel)
        let instruction = try loadPrompt(named: refinement.rawValue) {
            try prompts.read(.refinement(refinement))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let refinementPrompt = """
            \(systemPrompt)

            ## Additional instruction

            \(instruction)

            \(Self.refinementNote)
            """
        let (raw, _) = try await send(refinementPrompt, input: input)
        return try Self.polishedText(in: Self.decodeObject(raw))
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

    /// Runs `input` under `systemPrompt` on the routed model, returning the raw reply and the
    /// model used. The reply's tokens are recorded; a recording failure is logged and doesn't
    /// fail the request.
    private func send(
        _ systemPrompt: String, input: String,
        onText: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws(PolishError) -> (raw: String, model: String) {
        let model = ModelRouting.pickModel(for: input)
        let reply = try await runner.run(
            systemPrompt: systemPrompt, input: input, model: model, timeout: timeout,
            onText: onText)
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

    private func assemblePrompt(for channel: Channel) throws(PolishError) -> String {
        try loadPrompt(named: channel.rawValue) { try prompts.assemble(for: channel) }
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

    private static func parse(_ raw: String, model: String) throws(PolishError) -> PolishResult {
        let object = try decodeObject(raw)
        let polishedText = try polishedText(in: object)
        let wasTranslated = isTruthy(object["was_translated"])
        let summary = wasTranslated ? nil : try decodeSummary(object["learning_summary"])
        return PolishResult(
            polishedText: polishedText,
            learningSummary: summary,
            detectedLanguage: object["detected_language"] as? String ?? "Unknown",
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
