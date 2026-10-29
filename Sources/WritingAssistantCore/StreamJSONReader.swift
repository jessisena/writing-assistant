import Foundation
import os

/// The final `result` event of a `claude --output-format stream-json` run.
struct StreamResult: Sendable, Equatable {
    /// The full reply text, untrimmed; the error message when `isError` is true.
    let text: String
    let isError: Bool
    let usage: TokenUsage?
}

/// Reads the newline-delimited JSON events that `claude --output-format stream-json` prints.
///
/// Text deltas go to `onText` as soon as their line is read; the `result` event is kept. Lines
/// that aren't JSON objects are kept too, because claude prints some failures (e.g. "Not logged
/// in") as plain text. Every other event, thinking deltas included, is ignored.
final class StreamJSONReader: Sendable {
    private struct State {
        var hasEmittedText = false
        var result: StreamResult?
        var plainLines: [String] = []
    }

    private let onText: @Sendable (String) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(onText: @escaping @Sendable (String) -> Void) {
        self.onText = onText
    }

    /// Whether any text delta has been passed to `onText`.
    var hasEmittedText: Bool { state.withLock { $0.hasEmittedText } }

    var result: StreamResult? { state.withLock { $0.result } }

    /// The lines that weren't JSON objects, joined by newlines, or nil when there were none.
    var plainOutput: String? {
        let lines = state.withLock { $0.plainLines }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Handles one line of output, without its `\n`.
    func consume(_ line: Data) {
        let parsed = try? JSONSerialization.jsonObject(with: line)
        guard let event = parsed as? [String: Any] else {
            recordPlain(line)
            return
        }
        switch event["type"] as? String {
        case "stream_event":
            if let text = Self.textDelta(in: event) {
                state.withLock { $0.hasEmittedText = true }
                onText(text)
            }
        case "result":
            let result = Self.result(from: event)
            state.withLock { $0.result = result }
        default:
            break
        }
    }

    private func recordPlain(_ line: Data) {
        let text = String(decoding: line, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            state.withLock { $0.plainLines.append(text) }
        }
    }

    /// The text of a `content_block_delta` event carrying a `text_delta`.
    private static func textDelta(in event: [String: Any]) -> String? {
        guard let inner = event["event"] as? [String: Any],
            inner["type"] as? String == "content_block_delta",
            let delta = inner["delta"] as? [String: Any],
            delta["type"] as? String == "text_delta",
            let text = delta["text"] as? String, !text.isEmpty
        else {
            return nil
        }
        return text
    }

    private static func result(from event: [String: Any]) -> StreamResult {
        StreamResult(
            text: event["result"] as? String ?? "",
            isError: event["is_error"] as? Bool ?? false,
            usage: (event["usage"] as? [String: Any]).map(usage)
        )
    }

    private static func usage(from object: [String: Any]) -> TokenUsage {
        func count(_ key: String) -> Int { object[key] as? Int ?? 0 }
        return TokenUsage(
            input: count("input_tokens"),
            output: count("output_tokens"),
            cacheCreation: count("cache_creation_input_tokens"),
            cacheRead: count("cache_read_input_tokens")
        )
    }
}
