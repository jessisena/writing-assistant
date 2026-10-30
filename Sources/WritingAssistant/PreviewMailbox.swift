import WritingAssistantCore
import os

/// Hands polish previews from the thread the reply streams on to the main actor. It keeps only
/// the newest preview and at most one delivery in flight, so previews arrive in order and a busy
/// main actor gets one update instead of a backlog.
final class PreviewMailbox: Sendable {
    private struct State {
        var latest: PolishPreview?
        var isScheduled = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Keeps `preview` as the newest, replacing any not yet taken.
    ///
    /// - Returns: True when no delivery is scheduled, so the caller must schedule one that ends
    ///   with `take()`.
    func post(_ preview: PolishPreview) -> Bool {
        state.withLock { state in
            state.latest = preview
            defer { state.isScheduled = true }
            return !state.isScheduled
        }
    }

    /// Takes the newest preview and ends the scheduled delivery, so the next `post` schedules
    /// another.
    func take() -> PolishPreview? {
        state.withLock { state in
            let latest = state.latest
            state.latest = nil
            state.isScheduled = false
            return latest
        }
    }
}
