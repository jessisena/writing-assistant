#if DEBUG
    import Foundation
    import WritingAssistantCore

    /// In-memory `Polishing` for previews and tests. Sends `preview`, if set, then returns
    /// `outcome` after `delay`; `refine` returns its polished text.
    final class FakePolisher: Polishing, @unchecked Sendable {
        private let lock = NSLock()
        private var _outcome: Result<PolishResult, PolishError>
        private var _readiness: PolishError?
        private var _preview: PolishPreview?
        private var _calls: [(text: String, channel: Channel)] = []
        private var _summaryRequests: [Bool] = []
        private var _refineCalls: [(text: String, channel: Channel, refinement: Refinement)] = []
        let delay: Duration

        init(
            outcome: Result<PolishResult, PolishError> = .success(.sample),
            readiness: PolishError? = nil,
            preview: PolishPreview? = nil,
            delay: Duration = .zero
        ) {
            _outcome = outcome
            _readiness = readiness
            _preview = preview
            self.delay = delay
        }

        var preview: PolishPreview? {
            get { lock.withLock { _preview } }
            set { lock.withLock { _preview = newValue } }
        }

        /// The `includeLearningSummary` value of each `polish` call, in call order.
        var summaryRequests: [Bool] { lock.withLock { _summaryRequests } }

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

        func polish(
            text: String, channel: Channel, includeLearningSummary: Bool,
            onPreview: @escaping @Sendable (PolishPreview) -> Void
        ) async throws(PolishError) -> PolishResult {
            let preview = lock.withLock {
                _calls.append((text, channel))
                _summaryRequests.append(includeLearningSummary)
                return _preview
            }
            if let preview {
                onPreview(preview)
            }
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

    /// `Polishing` whose calls wait until `resume(_:with:)` answers them, for tests that need a
    /// request to stay in flight.
    ///
    /// Like a `claude` child that hasn't exited yet, a waiting call ignores task cancellation;
    /// it only counts it in `cancelledCount`.
    final class GatedPolisher: Polishing, @unchecked Sendable {
        private typealias Gate = CheckedContinuation<Result<PolishResult, PolishError>, Never>

        private let lock = NSLock()
        private var gates: [Gate] = []
        private var previewSinks: [@Sendable (PolishPreview) -> Void] = []
        private var _cancelledCount = 0

        /// Calls made so far, each waiting until resumed.
        var waitingCount: Int { lock.withLock { gates.count } }

        var cancelledCount: Int { lock.withLock { _cancelledCount } }

        /// Answers the call at `index`, in call order. Each call must be answered once.
        func resume(_ index: Int, with outcome: Result<PolishResult, PolishError>) {
            let gate = lock.withLock { gates[index] }
            gate.resume(returning: outcome)
        }

        /// Sends `preview` to the `onPreview` of the call at `index`, which keeps waiting.
        func sendPreview(_ index: Int, _ preview: PolishPreview) {
            let sink = lock.withLock { previewSinks[index] }
            sink(preview)
        }

        func polish(
            text: String, channel: Channel, includeLearningSummary: Bool,
            onPreview: @escaping @Sendable (PolishPreview) -> Void
        ) async throws(PolishError) -> PolishResult {
            try await wait(onPreview: onPreview)
        }

        func refine(
            text: String, channel: Channel, refinement: Refinement
        ) async throws(PolishError) -> String {
            try await wait(onPreview: { _ in }).polishedText
        }

        private func wait(
            onPreview: @escaping @Sendable (PolishPreview) -> Void
        ) async throws(PolishError) -> PolishResult {
            let outcome = await withTaskCancellationHandler {
                await withCheckedContinuation { gate in
                    lock.withLock {
                        gates.append(gate)
                        previewSinks.append(onPreview)
                    }
                }
            } onCancel: {
                lock.withLock { _cancelledCount += 1 }
            }
            return try outcome.get()
        }

        func checkReady() async throws(PolishError) {}
    }

    /// In-memory `PromptStoring` that applies the same validation as the real store.
    ///
    /// `syncDefaults()` returns the files in `newerDefaults`; acknowledging or restoring a file
    /// removes it. Set `acknowledgeFailure` to make `acknowledgeDefault(_:)` throw.
    final class FakePromptStore: PromptStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var files: [PromptFile: String]
        private let defaults: [PromptFile: String]
        private var _newerDefaults: Set<PromptFile>
        private var _acknowledgeFailure: (any Error)?
        let directoryURL = URL(fileURLWithPath: "/tmp/fake-prompts")

        init(files: [PromptFile: String]? = nil, newerDefaults: Set<PromptFile> = []) {
            var seeded: [PromptFile: String] = [.global: "Rules\n\(PromptFile.channelPlaceholder)"]
            for channel in Channel.allCases {
                seeded[.channel(channel)] = "\(channel.rawValue) guidelines"
            }
            for refinement in Refinement.allCases {
                seeded[.refinement(refinement)] = "\(refinement.rawValue) instruction"
            }
            defaults = seeded
            self.files = files ?? seeded
            _newerDefaults = newerDefaults
        }

        var newerDefaults: Set<PromptFile> { lock.withLock { _newerDefaults } }

        var acknowledgeFailure: (any Error)? {
            get { lock.withLock { _acknowledgeFailure } }
            set { lock.withLock { _acknowledgeFailure = newValue } }
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
            lock.withLock {
                files[file] = defaults[file]
                _newerDefaults.remove(file)
            }
        }

        func syncDefaults() throws -> Set<PromptFile> {
            newerDefaults
        }

        func acknowledgeDefault(_ file: PromptFile) throws {
            try lock.withLock {
                if let _acknowledgeFailure { throw _acknowledgeFailure }
                _newerDefaults.remove(file)
            }
        }

        func assemble(for channel: Channel) throws -> String {
            let global = try read(.global).trimmingCharacters(in: .whitespacesAndNewlines)
            let rules = try read(.channel(channel)).trimmingCharacters(in: .whitespacesAndNewlines)
            return global.replacingOccurrences(of: PromptFile.channelPlaceholder, with: rules)
        }
    }

    extension PolishResult {
        static let sample = PolishResult(
            polishedText: """
                Thanks for the **update**. I'll review the doc *today*:
                - Read the summary
                - Leave comments 👍
                """,
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
