import Foundation
import os

/// Runs the polish pipeline: validate input, assemble the prompt, call Claude, parse the reply.
public struct PolishService: Polishing {
    public static let maxInputLength = 20_000
    public static let defaultTimeout: Duration = .seconds(120)

    private static let logger = Logger(subsystem: "local.writing-assistant", category: "pipeline")

    private let runner: any ClaudeRunning
    private let prompts: any PromptStoring
    private let timeout: Duration

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - runner: Executes prompts against the claude CLI.
    ///   - prompts: Supplies the assembled system prompt for each channel.
    ///   - timeout: Upper bound for a single Claude call.
    public init(
        runner: any ClaudeRunning,
        prompts: any PromptStoring,
        timeout: Duration = PolishService.defaultTimeout
    ) {
        self.runner = runner
        self.prompts = prompts
        self.timeout = timeout
    }

    /// Polishes (or translates, then polishes) `text` for `channel`.
    ///
    /// When the model reports `was_translated: true`, the result never carries a learning
    /// summary, whatever the model returned.
    ///
    /// - Parameters:
    ///   - text: The user's input. Leading and trailing whitespace is ignored.
    ///   - channel: Selects the channel guidelines inserted into the prompt.
    /// - Returns: The parsed result, including the model that produced it.
    /// - Throws: `.emptyInput`, `.inputTooLong`, `.promptUnavailable`, `.badFormat`, or any
    ///   error thrown by the runner, unchanged.
    public func polish(text: String, channel: Channel) async throws(PolishError) -> PolishResult {
        let input = try Self.validatedInput(text)
        let systemPrompt = try assemblePrompt(for: channel)
        let model = ModelRouting.pickModel(for: input)
        let raw = try await runner.run(
            prompt: "\(systemPrompt)\n\n---\n\n\(input)", model: model, timeout: timeout)
        return try Self.parse(raw, model: model)
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

    private func assemblePrompt(for channel: Channel) throws(PolishError) -> String {
        do {
            return try prompts.assemble(for: channel)
        } catch {
            let detail = error.localizedDescription
            let name = channel.rawValue
            Self.logger.error(
                "Prompt unavailable for \(name, privacy: .public): \(detail, privacy: .public)")
            throw .promptUnavailable(detail: detail)
        }
    }

    private static func parse(_ raw: String, model: String) throws(PolishError) -> PolishResult {
        let object = try decodeObject(raw)
        guard let polishedText = object["polished_text"] as? String else {
            throw badFormat("missing or non-string polished_text")
        }
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
