import Foundation

// Shared public API between the Core implementations and the SwiftUI app.

public enum Channel: String, CaseIterable, Sendable, Identifiable {
    case slack
    case slackInformal = "slack_informal"
    case talkingPoints = "talking_points"
    case formal
    case aiPrompt = "ai_prompt"
    case email
    case personalMessage = "personal_message"
    case proofread
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .slack: "Slack message"
        case .slackInformal: "Informal Slack message"
        case .talkingPoints: "Sync / meeting talking points"
        case .formal: "Formal document"
        case .aiPrompt: "AI prompt"
        case .email: "Email"
        case .personalMessage: "Personal message (text, WhatsApp)"
        case .proofread: "Proofread only"
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
        case .email: "Email"
        case .personalMessage: "Personal"
        case .proofread: "Proofread"
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
    /// Nil unless the request's `PolishOptions` allow one for this language (enforced by
    /// `PolishService`): always nil for a translation or non-English input.
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

/// The tokens used in one calendar month, what they cost and how many requests used them.
public struct MonthlyUsage: Codable, Sendable, Equatable {
    public var tokens: TokenUsage
    public var requests: Int
    /// What the tokens cost at API list prices, in US dollars, as the claude CLI priced them.
    public var costUSD: Double

    public static let zero = MonthlyUsage(tokens: .zero, requests: 0, costUSD: 0)

    public init(tokens: TokenUsage, requests: Int, costUSD: Double) {
        self.tokens = tokens
        self.requests = requests
        self.costUSD = costUSD
    }
}

/// What the claude CLI answered: the reply text and, when reported, the tokens it used and their
/// cost at API list prices in US dollars.
public struct ClaudeReply: Sendable, Equatable {
    public var text: String
    public var usage: TokenUsage?
    public var costUSD: Double?

    public init(text: String, usage: TokenUsage?, costUSD: Double? = nil) {
        self.text = text
        self.usage = usage
        self.costUSD = costUSD
    }
}

/// What the reply of a polish request that is still running has said so far. Each field is nil
/// until the reply states it.
public struct PolishPreview: Sendable, Equatable {
    /// The top-level `polished_text`, unescaped, as far as it has arrived: "" once its string
    /// opens, then longer with every update. Never ends in half an escape.
    public var polishedText: String?
    /// True once the `polished_text` string has closed, so `polishedText` is the whole text.
    public var isTextComplete: Bool
    public var detectedLanguage: String?
    public var wasTranslated: Bool?

    public init(
        polishedText: String? = nil, isTextComplete: Bool = false,
        detectedLanguage: String? = nil, wasTranslated: Bool? = nil
    ) {
        self.polishedText = polishedText
        self.isTextComplete = isTextComplete
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
    /// The installed claude rejected a flag this app passes; `detail` is what it printed.
    case cliOutdated(detail: String)
    case badFormat(detail: String)
    case promptUnavailable(detail: String)
    /// A custom refinement instruction was blank.
    case emptyInstruction
    /// A custom refinement instruction had more than `limit` characters.
    case instructionTooLong(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Please paste some text before processing."
        case .inputTooLong(let limit):
            "Text is too long. The limit is \(limit.formatted()) characters."
        case .emptyInstruction:
            "Type what to change before refining."
        case .instructionTooLong(let limit):
            "That refine instruction is too long. The limit is \(limit.formatted()) characters."
        case .claudeNotFound:
            "claude CLI not found. Install it from https://claude.ai/download and make sure "
                + "`claude --version` works in a terminal, then try again."
        case .timeout(let seconds):
            "Claude took longer than \(seconds) seconds. Please try again."
        case .cliFailed:
            "Claude returned an error. Check the logs."
        case .cliOutdated:
            "Your Claude Code is too old for this app. Update it by running `claude update` in a "
                + "terminal, then try again."
        case .badFormat:
            "Unexpected response format from Claude. Check the logs."
        case .promptUnavailable(let detail):
            "Couldn't read the prompt files (\(detail)). Open Settings (⌘,) to restore them."
        }
    }
}

public enum PromptFile: Hashable, Sendable, Identifiable {
    /// `polish.txt`: the polish prompt, with slots for the other sections.
    case global
    /// `always.txt`: the rules shared by the polish and refine prompts.
    case always
    /// `learning_summary.txt`: inserted into the polish prompt only while the summary is on.
    case learningSummary
    /// `refine.txt`: the refine prompt, with slots for the shared rules, channel and instruction.
    case refine
    case channel(Channel)
    case refinement(Refinement)
    /// `modes/<mode>.txt`: the tone baseline inserted into the polish prompt for that mode.
    case mode(Mode)
    /// `languages/<policy>.txt`: the language rules inserted into the polish prompt.
    case languagePolicy(OutputLanguage)

    public static let channelPlaceholder = "{{CHANNEL_GUIDELINES}}"
    public static let alwaysPlaceholder = "{{ALWAYS_RULES}}"
    public static let learningSummaryPlaceholder = "{{LEARNING_SUMMARY}}"
    public static let instructionPlaceholder = "{{REFINEMENT_INSTRUCTION}}"
    public static let modePlaceholder = "{{MODE_GUIDELINES}}"
    public static let languagePolicyPlaceholder = "{{LANGUAGE_POLICY}}"

    public static var allCases: [PromptFile] {
        [.global, .always, .learningSummary, .refine] + Channel.allCases.map { .channel($0) }
            + Refinement.allCases.map { .refinement($0) } + Mode.allCases.map { .mode($0) }
            + OutputLanguage.allCases.map { .languagePolicy($0) }
    }

    public var id: String { relativePath }

    /// Path relative to the prompts directory, e.g. `polish.txt`, `channels/slack.txt` or
    /// `refinements/shorter.txt`.
    public var relativePath: String {
        switch self {
        case .global: "polish.txt"
        case .always: "always.txt"
        case .learningSummary: "learning_summary.txt"
        case .refine: "refine.txt"
        case .channel(let channel): "channels/\(channel.rawValue).txt"
        case .refinement(let refinement): "refinements/\(refinement.rawValue).txt"
        case .mode(let mode): "modes/\(mode.rawValue).txt"
        case .languagePolicy(let language): "languages/\(language.fileName).txt"
        }
    }

    public var displayName: String {
        switch self {
        case .global: "Polish prompt"
        case .always: "Always rules"
        case .learningSummary: "Learning summary"
        case .refine: "Refine prompt"
        case .channel(let channel): channel.displayName
        case .refinement(let refinement): refinement.displayName
        case .mode(let mode): "\(mode.displayName) mode tone"
        case .languagePolicy(let language): "Language: \(language.displayName)"
        }
    }

    /// The placeholder a saved copy must keep, because the request is pointless without it.
    public var requiredPlaceholder: String? {
        switch self {
        case .global: Self.channelPlaceholder
        case .refine: Self.instructionPlaceholder
        default: nil
        }
    }

    /// Rules every saved prompt must satisfy.
    public func validate(_ text: String) throws(PromptValidationError) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .empty
        }
        if let placeholder = requiredPlaceholder, !text.contains(placeholder) {
            throw .missingPlaceholder(placeholder)
        }
    }
}

public enum PromptValidationError: LocalizedError, Equatable, Sendable {
    case empty
    /// The text lacks this placeholder, which the file must keep.
    case missingPlaceholder(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            "A prompt can't be empty."
        case .missingPlaceholder(let placeholder):
            "This prompt must contain \(placeholder) so the "
                + "\(Self.insertedPart(placeholder)) can be inserted."
        }
    }

    private static func insertedPart(_ placeholder: String) -> String {
        placeholder == PromptFile.instructionPlaceholder
            ? "refinement instruction" : "channel guidelines"
    }
}

/// Runs one request through the claude CLI and returns its reply.
/// Throws `PolishError.claudeNotFound`, `.timeout`, `.cliOutdated`, or `.cliFailed`.
public protocol ClaudeRunning: Sendable {
    /// Sends `input` as the user turn under `systemPrompt`, which replaces Claude Code's own.
    /// `onText` receives the reply text in order, piece by piece, while it is generated.
    func run(
        systemPrompt: String, input: String, model: String, timeout: Duration,
        onText: @escaping @Sendable (String) -> Void
    ) async throws(PolishError) -> ClaudeReply
    /// Throws `PolishError.claudeNotFound` when the CLI can't be located.
    func checkAvailable() async throws(PolishError)
}

/// Keeps count of the tokens Claude requests use and what they cost.
public protocol UsageRecording: Sendable {
    /// Adds one request. A nil `costUSD` (the CLI didn't price the run) adds nothing to the cost.
    func record(_ usage: TokenUsage, costUSD: Double?) throws
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
}

public protocol Polishing: Sendable {
    /// Polishes `text` for `channel`.
    ///
    /// - Parameters:
    ///   - options: The mode's tone, the output language and whether to ask for a learning
    ///     summary. The result only has a summary when
    ///     `options.allowsLearningSummary(detectedLanguage:wasTranslated:)` holds for it.
    ///   - onPreview: Called, one call at a time and in order, with what the reply has said so
    ///     far, each time a streamed piece changes it, and never after the method returns. The
    ///     polished text grows until `isTextComplete`; the language fields can still change after
    ///     that, while the rest of the reply (the learning summary) is coming.
    func polish(
        text: String, channel: Channel, options: PolishOptions,
        onPreview: @escaping @Sendable (PolishPreview) -> Void
    ) async throws(PolishError) -> PolishResult
    /// Rewrites already-polished `text` for `channel` with one extra instruction, a preset or
    /// the user's own, and returns only the new polished text.
    func refine(
        text: String, channel: Channel, refinement: RefinementInstruction
    ) async throws(PolishError) -> String
    /// Throws `PolishError.claudeNotFound` when the CLI can't be located.
    func checkReady() async throws(PolishError)
}
