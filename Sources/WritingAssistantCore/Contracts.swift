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

    /// A label short enough for a chip.
    public var shortName: String {
        switch self {
        case .slack: "Slack"
        case .slackInformal: "Casual Slack"
        case .talkingPoints: "Talking points"
        case .formal: "Formal doc"
        case .aiPrompt: "AI prompt"
        case .other: "General"
        }
    }
}

/// A quick follow-up edit applied to text that was already polished.
public enum Refinement: String, CaseIterable, Sendable, Identifiable {
    case shorter
    case moreCasual = "more_casual"
    case moreFormal = "more_formal"
    case moreDiplomatic = "more_diplomatic"
    case moreAssertive = "more_assertive"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shorter: "Shorter"
        case .moreCasual: "More casual"
        case .moreFormal: "More formal"
        case .moreDiplomatic: "More diplomatic"
        case .moreAssertive: "More assertive"
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

/// Tokens one or more Claude requests used, as the claude CLI reports them.
public struct TokenUsage: Codable, Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int

    public static let zero = TokenUsage(input: 0, output: 0, cacheCreation: 0, cacheRead: 0)

    public init(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }

    /// Every token sent or received, cached or not.
    public var total: Int { input + output + cacheCreation + cacheRead }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }
}

/// The tokens used in one calendar month and how many requests used them.
public struct MonthlyUsage: Codable, Sendable, Equatable {
    public var tokens: TokenUsage
    public var requests: Int

    public static let zero = MonthlyUsage(tokens: .zero, requests: 0)

    public init(tokens: TokenUsage, requests: Int) {
        self.tokens = tokens
        self.requests = requests
    }
}

/// What the claude CLI answered: the reply text and, when reported, the tokens it used.
public struct ClaudeReply: Sendable, Equatable {
    public var text: String
    public var usage: TokenUsage?

    public init(text: String, usage: TokenUsage?) {
        self.text = text
        self.usage = usage
    }
}

/// The polished text of a polish request that is still running, sent as soon as the reply's
/// `polished_text` is complete. The language fields are nil when the reply hadn't stated them yet.
public struct PolishPreview: Sendable, Equatable {
    public var polishedText: String
    public var detectedLanguage: String?
    public var wasTranslated: Bool?

    public init(polishedText: String, detectedLanguage: String?, wasTranslated: Bool?) {
        self.polishedText = polishedText
        self.detectedLanguage = detectedLanguage
        self.wasTranslated = wasTranslated
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

/// Runs one prompt through the claude CLI and returns its reply.
/// Throws `PolishError.claudeNotFound`, `.timeout`, or `.cliFailed`.
public protocol ClaudeRunning: Sendable {
    /// `onText` receives the reply text in order, piece by piece, while it is generated.
    func run(
        prompt: String, model: String, timeout: Duration,
        onText: @escaping @Sendable (String) -> Void
    ) async throws(PolishError) -> ClaudeReply
    /// Throws `PolishError.claudeNotFound` when the CLI can't be located.
    func checkAvailable() async throws(PolishError)
}

extension ClaudeRunning {
    /// Runs `prompt` without watching the reply as it is generated.
    public func run(prompt: String, model: String, timeout: Duration) async throws(PolishError)
        -> ClaudeReply
    {
        try await run(prompt: prompt, model: model, timeout: timeout, onText: { _ in })
    }
}

/// Keeps count of the tokens Claude requests use.
public protocol UsageRecording: Sendable {
    func record(_ usage: TokenUsage) throws
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
    /// Updates unedited files to changed bundled defaults. Returns the edited files that have a
    /// newer default the user hasn't taken.
    func syncDefaults() throws -> Set<PromptFile>
    /// Marks the current bundled default as seen without changing the file ("Keep mine").
    func acknowledgeDefault(_ file: PromptFile) throws
    /// `polish.txt` with the placeholder replaced by the channel file (both trimmed).
    func assemble(for channel: Channel) throws -> String
}

public protocol Polishing: Sendable {
    /// Polishes `text` for `channel`.
    ///
    /// - Parameters:
    ///   - includeLearningSummary: False asks for no learning summary, and the result has none.
    ///   - onPreview: Called at most once, before the method returns, as soon as the polished
    ///     text is complete, while the rest of the reply (the learning summary) is still coming.
    func polish(
        text: String, channel: Channel, includeLearningSummary: Bool,
        onPreview: @escaping @Sendable (PolishPreview) -> Void
    ) async throws(PolishError) -> PolishResult
    /// Rewrites already-polished `text` for `channel` with one extra instruction and returns
    /// only the new polished text.
    func refine(text: String, channel: Channel, refinement: Refinement) async throws(PolishError)
        -> String
    /// Throws `PolishError.claudeNotFound` when the CLI can't be located.
    func checkReady() async throws(PolishError)
}

extension Polishing {
    /// Polishes `text` for `channel` with a learning summary and no preview.
    public func polish(text: String, channel: Channel) async throws(PolishError) -> PolishResult {
        try await polish(
            text: text, channel: channel, includeLearningSummary: true, onPreview: { _ in })
    }
}
