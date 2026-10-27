import Foundation

// Shared public API between the Core implementations and the SwiftUI app.

public enum Channel: String, CaseIterable, Sendable, Identifiable {
    case slack
    case slackInformal = "slack_informal"
    case talkingPoints = "talking_points"
    case formal
    case aiPrompt = "ai_prompt"
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .slack: "Slack message"
        case .slackInformal: "Informal Slack message"
        case .talkingPoints: "Sync / meeting talking points"
        case .formal: "Formal document"
        case .aiPrompt: "AI prompt"
        case .other: "Other / general"
        }
    }
}

/// A quick follow-up edit applied to text that was already polished.
public enum Refinement: String, CaseIterable, Sendable, Identifiable {
    case shorter
    case moreCasual = "more_casual"
    case moreFormal = "more_formal"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shorter: "Shorter"
        case .moreCasual: "More casual"
        case .moreFormal: "More formal"
        }
    }
}

public struct Correction: Codable, Sendable, Equatable {
    public var original: String
    public var corrected: String
    public var why: String

    public init(original: String, corrected: String, why: String) {
        self.original = original
        self.corrected = corrected
        self.why = why
    }
}

public struct VocabularyItem: Codable, Sendable, Equatable {
    public var term: String
    public var meaning: String
    public var example: String

    public init(term: String, meaning: String, example: String) {
        self.term = term
        self.meaning = meaning
        self.example = example
    }
}

public struct LearningSummary: Codable, Sendable, Equatable {
    public var corrections: [Correction]
    public var grammarInsight: String
    public var vocabulary: [VocabularyItem]

    enum CodingKeys: String, CodingKey {
        case corrections
        case grammarInsight = "grammar_insight"
        case vocabulary
    }

    public init(corrections: [Correction], grammarInsight: String, vocabulary: [VocabularyItem]) {
        self.corrections = corrections
        self.grammarInsight = grammarInsight
        self.vocabulary = vocabulary
    }

    public var isEmpty: Bool {
        corrections.isEmpty && grammarInsight.isEmpty && vocabulary.isEmpty
    }
}

public struct PolishResult: Sendable, Equatable {
    public var polishedText: String
    /// Always nil when `wasTranslated` is true (enforced by `PolishService`).
    public var learningSummary: LearningSummary?
    public var detectedLanguage: String
    public var wasTranslated: Bool
    public var modelUsed: String

    public init(
        polishedText: String,
        learningSummary: LearningSummary?,
        detectedLanguage: String,
        wasTranslated: Bool,
        modelUsed: String
    ) {
        self.polishedText = polishedText
        self.learningSummary = learningSummary
        self.detectedLanguage = detectedLanguage
        self.wasTranslated = wasTranslated
        self.modelUsed = modelUsed
    }
}

public enum PolishError: LocalizedError, Equatable, Sendable {
    case emptyInput
    case inputTooLong(limit: Int)
    case claudeNotFound
    case timeout(seconds: Int)
    case cliFailed(stderr: String)
    case badFormat(detail: String)
    case promptUnavailable(detail: String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Please paste some text before processing."
        case .inputTooLong(let limit):
            "Text is too long. The limit is \(limit.formatted()) characters."
        case .claudeNotFound:
            "claude CLI not found. Install it from https://claude.ai/download and make sure "
                + "`claude --version` works in a terminal, then try again."
        case .timeout(let seconds):
            "Claude took longer than \(seconds) seconds. Please try again."
        case .cliFailed:
            "Claude returned an error. Check the logs."
        case .badFormat:
            "Unexpected response format from Claude. Check the logs."
        case .promptUnavailable(let detail):
            "Couldn't read the prompt files (\(detail)). Open Settings (⌘,) to restore them."
        }
    }
}

public enum PromptFile: Hashable, Sendable, Identifiable {
    case global
    case channel(Channel)
    case refinement(Refinement)

    public static let channelPlaceholder = "{{CHANNEL_GUIDELINES}}"

    public static var allCases: [PromptFile] {
        [.global] + Channel.allCases.map { .channel($0) }
            + Refinement.allCases.map { .refinement($0) }
    }

    public var id: String { relativePath }

    /// Path relative to the prompts directory, e.g. `polish.txt`, `channels/slack.txt` or
    /// `refinements/shorter.txt`.
    public var relativePath: String {
        switch self {
        case .global: "polish.txt"
        case .channel(let channel): "channels/\(channel.rawValue).txt"
        case .refinement(let refinement): "refinements/\(refinement.rawValue).txt"
        }
    }

    public var displayName: String {
        switch self {
        case .global: "Global rules"
        case .channel(let channel): channel.displayName
        case .refinement(let refinement): refinement.displayName
        }
    }

    /// Rules every saved prompt must satisfy.
    public func validate(_ text: String) throws(PromptValidationError) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .empty
        }
        if self == .global && !text.contains(Self.channelPlaceholder) {
            throw .missingPlaceholder
        }
    }
}

public enum PromptValidationError: LocalizedError, Equatable, Sendable {
    case empty
    case missingPlaceholder

    public var errorDescription: String? {
        switch self {
        case .empty:
            "A prompt can't be empty."
        case .missingPlaceholder:
            "Global rules must contain \(PromptFile.channelPlaceholder) "
                + "so the channel guidelines can be inserted."
        }
    }
}

/// Runs one prompt through the claude CLI and returns its stdout.
/// Throws `PolishError.claudeNotFound`, `.timeout`, or `.cliFailed`.
public protocol ClaudeRunning: Sendable {
    func run(prompt: String, model: String, timeout: Duration) async throws(PolishError) -> String
    /// Throws `PolishError.claudeNotFound` when the CLI can't be located.
    func checkAvailable() async throws(PolishError)
}

/// Prompt files on disk. Every read goes to disk, so external edits apply immediately.
public protocol PromptStoring: Sendable {
    var directoryURL: URL { get }
    func fileURL(_ file: PromptFile) -> URL
    /// Copies bundled defaults for files that don't exist yet. Never overwrites.
    func seedMissingDefaults() throws
    func read(_ file: PromptFile) throws -> String
    /// Validates with `PromptFile.validate` before writing.
    func write(_ text: String, to file: PromptFile) throws
    func restoreDefault(_ file: PromptFile) throws
    /// `polish.txt` with the placeholder replaced by the channel file (both trimmed).
    func assemble(for channel: Channel) throws -> String
}

public protocol Polishing: Sendable {
    func polish(text: String, channel: Channel) async throws(PolishError) -> PolishResult
    /// Rewrites already-polished `text` for `channel` with one extra instruction and returns
    /// only the new polished text.
    func refine(text: String, channel: Channel, refinement: Refinement) async throws(PolishError)
        -> String
    /// Throws `PolishError.claudeNotFound` when the CLI can't be located.
    func checkReady() async throws(PolishError)
}
