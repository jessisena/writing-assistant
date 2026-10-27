#if DEBUG
    import Foundation
    import WritingAssistantCore

    /// In-memory `Polishing` for previews and tests. Returns `outcome` after `delay`; `refine`
    /// returns its polished text.
    final class FakePolisher: Polishing, @unchecked Sendable {
        private let lock = NSLock()
        private var _outcome: Result<PolishResult, PolishError>
        private var _readiness: PolishError?
        private var _calls: [(text: String, channel: Channel)] = []
        private var _refineCalls: [(text: String, channel: Channel, refinement: Refinement)] = []
        let delay: Duration

        init(
            outcome: Result<PolishResult, PolishError> = .success(.sample),
            readiness: PolishError? = nil,
            delay: Duration = .zero
        ) {
            _outcome = outcome
            _readiness = readiness
            self.delay = delay
        }

        var outcome: Result<PolishResult, PolishError> {
            get { lock.withLock { _outcome } }
            set { lock.withLock { _outcome = newValue } }
        }

        var readiness: PolishError? {
            get { lock.withLock { _readiness } }
            set { lock.withLock { _readiness = newValue } }
        }

        var calls: [(text: String, channel: Channel)] { lock.withLock { _calls } }

        var refineCalls: [(text: String, channel: Channel, refinement: Refinement)] {
            lock.withLock { _refineCalls }
        }

        func polish(text: String, channel: Channel) async throws(PolishError) -> PolishResult {
            lock.withLock { _calls.append((text, channel)) }
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            return try outcome.get()
        }

        func refine(
            text: String, channel: Channel, refinement: Refinement
        ) async throws(PolishError) -> String {
            lock.withLock { _refineCalls.append((text, channel, refinement)) }
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            return try outcome.get().polishedText
        }

        func checkReady() async throws(PolishError) {
            if let readiness { throw readiness }
        }
    }

    /// In-memory `PromptStoring` that applies the same validation as the real store.
    final class FakePromptStore: PromptStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var files: [PromptFile: String]
        private let defaults: [PromptFile: String]
        let directoryURL = URL(fileURLWithPath: "/tmp/fake-prompts")

        init(files: [PromptFile: String]? = nil) {
            var seeded: [PromptFile: String] = [.global: "Rules\n\(PromptFile.channelPlaceholder)"]
            for channel in Channel.allCases {
                seeded[.channel(channel)] = "\(channel.rawValue) guidelines"
            }
            for refinement in Refinement.allCases {
                seeded[.refinement(refinement)] = "\(refinement.rawValue) instruction"
            }
            defaults = seeded
            self.files = files ?? seeded
        }

        func fileURL(_ file: PromptFile) -> URL {
            directoryURL.appending(path: file.relativePath)
        }

        func seedMissingDefaults() throws {
            lock.withLock {
                for (file, text) in defaults where files[file] == nil {
                    files[file] = text
                }
            }
        }

        func read(_ file: PromptFile) throws -> String {
            let text = lock.withLock { files[file] }
            guard let text else { throw CocoaError(.fileNoSuchFile) }
            return text
        }

        func write(_ text: String, to file: PromptFile) throws {
            try file.validate(text)
            lock.withLock { files[file] = text }
        }

        func restoreDefault(_ file: PromptFile) throws {
            lock.withLock { files[file] = defaults[file] }
        }

        func assemble(for channel: Channel) throws -> String {
            let global = try read(.global).trimmingCharacters(in: .whitespacesAndNewlines)
            let rules = try read(.channel(channel)).trimmingCharacters(in: .whitespacesAndNewlines)
            return global.replacingOccurrences(of: PromptFile.channelPlaceholder, with: rules)
        }
    }

    extension PolishResult {
        static let sample = PolishResult(
            polishedText: "Thanks for the update. I'll review the doc today.",
            learningSummary: LearningSummary(
                corrections: [
                    Correction(
                        original: "I will to review",
                        corrected: "I'll review",
                        why: "\"will\" is followed by the bare infinitive, without \"to\"."
                    )
                ],
                grammarInsight: "Modal verbs take the base form of the verb.",
                vocabulary: [
                    VocabularyItem(
                        term: "heads-up",
                        meaning: "an advance warning",
                        example: "Thanks for the heads-up."
                    )
                ]
            ),
            detectedLanguage: "English",
            wasTranslated: false,
            modelUsed: ModelRouting.haikuModel
        )
    }
#endif
