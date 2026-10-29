import Observation

/// Keeps track of the one request that may run at a time: whether it is running, the task that
/// `cancel()` stops, and a generation number so a request that was cancelled or replaced can't
/// overwrite a newer one when it finishes.
@Observable @MainActor final class RequestRunner {
    private(set) var isRunning = false
    /// The task started by `start(_:)`, which `cancel()` stops.
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// Marks a request as running.
    ///
    /// - Returns: The request's generation for `finish(_:_:)`, or nil when a request is already
    ///   running.
    func begin() -> Int? {
        guard !isRunning else { return nil }
        isRunning = true
        generation += 1
        return generation
    }

    /// Whether the request started as `generation` is still running: not finished, cancelled or
    /// replaced.
    func isCurrent(_ generation: Int) -> Bool {
        isRunning && generation == self.generation
    }

    /// Runs `work` in a task that `cancel()` can stop. Call it after `begin()` succeeded.
    func start(_ work: @escaping @MainActor () async -> Void) {
        task = Task { await work() }
    }

    /// Runs the work of the request started as `generation` and ends its running state.
    ///
    /// - Returns: The operation's outcome, or nil when the request was cancelled or replaced by
    ///   a newer one, in which case nothing changes.
    func finish<Value, Failure: Error>(
        _ generation: Int, _ operation: () async throws(Failure) -> Value
    ) async -> Result<Value, Failure>? {
        let outcome: Result<Value, Failure>
        do {
            outcome = .success(try await operation())
        } catch {
            outcome = .failure(error)
        }
        guard generation == self.generation else { return nil }
        isRunning = false
        guard !Task.isCancelled else { return nil }
        return outcome
    }

    /// Stops the running request. Its late answer is ignored. Does nothing when idle.
    func cancel() {
        guard isRunning else { return }
        task?.cancel()
        generation += 1
        isRunning = false
    }
}
