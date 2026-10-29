import Testing

@testable import WritingAssistant

@MainActor
@Suite struct RequestRunnerTests {
    private struct Failed: Error, Equatable {}

    /// Holds what a request started with `start(_:)` finished with.
    @MainActor private final class Outcome {
        var value: Result<Int, Never>?
        var finished = false
    }

    @Test func beginWhileRunningIsRefused() {
        let runner = RequestRunner()

        #expect(runner.begin() != nil)
        #expect(runner.begin() == nil)
        #expect(runner.isRunning)
    }

    @Test func isCurrentOnlyWhileThatGenerationRuns() async throws {
        let runner = RequestRunner()
        let first = try #require(runner.begin())
        #expect(runner.isCurrent(first))

        runner.cancel()
        let second = try #require(runner.begin())
        #expect(!runner.isCurrent(first))
        #expect(runner.isCurrent(second))

        _ = await runner.finish(second) { () async throws(Never) in 1 }
        #expect(!runner.isCurrent(second))
    }

    @Test func finishReturnsTheValueAndEndsRunning() async throws {
        let runner = RequestRunner()
        let generation = try #require(runner.begin())

        let outcome = await runner.finish(generation) { () async throws(Never) in 1 }

        #expect(outcome == .success(1))
        #expect(!runner.isRunning)
    }

    @Test func finishReturnsTheFailure() async throws {
        let runner = RequestRunner()
        let generation = try #require(runner.begin())

        let outcome = await runner.finish(generation) { () async throws(Failed) -> Int in
            throw Failed()
        }

        #expect(outcome == .failure(Failed()))
        #expect(!runner.isRunning)
    }

    @Test func cancelEndsRunningAndTheRequestFinishesWithNothing() async throws {
        let runner = RequestRunner()
        let outcome = Outcome()
        let generation = try #require(runner.begin())
        runner.start {
            outcome.value = await runner.finish(generation) { () async throws(Never) in
                try? await Task.sleep(for: .seconds(60))
                return 1
            }
            outcome.finished = true
        }

        runner.cancel()

        #expect(!runner.isRunning)
        await runner.task?.value
        #expect(outcome.finished)
        #expect(outcome.value == nil)
    }

    @Test func staleRequestFinishingLateDoesNotEndTheNewerOne() async throws {
        let runner = RequestRunner()
        let stale = try #require(runner.begin())
        runner.cancel()
        let newer = try #require(runner.begin())

        let staleOutcome = await runner.finish(stale) { () async throws(Never) in 1 }

        #expect(staleOutcome == nil)
        #expect(runner.isRunning)
        let newerOutcome = await runner.finish(newer) { () async throws(Never) in 2 }
        #expect(newerOutcome == .success(2))
        #expect(!runner.isRunning)
    }

    @Test func newRequestAfterCancelRuns() async throws {
        let runner = RequestRunner()
        let outcome = Outcome()
        _ = try #require(runner.begin())
        runner.cancel()

        let generation = try #require(runner.begin())
        runner.start {
            outcome.value = await runner.finish(generation) { () async throws(Never) in 2 }
        }
        await runner.task?.value

        #expect(outcome.value == .success(2))
        #expect(!runner.isRunning)
    }

    @Test func cancelWhenIdleDoesNothing() {
        let runner = RequestRunner()

        runner.cancel()

        #expect(!runner.isRunning)
        #expect(runner.begin() != nil)
    }
}
