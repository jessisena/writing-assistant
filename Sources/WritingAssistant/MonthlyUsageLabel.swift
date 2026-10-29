import SwiftUI
import WritingAssistantCore

/// The month's token total as one quiet toolbar line, with the breakdown in its tooltip.
struct MonthlyUsageLabel: View {
    let model: AppModel

    var body: some View {
        let usage = model.monthlyUsage
        Text(usage.compactSummary())
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
            .padding(.horizontal, 6)
            .help(usage.breakdown())
            .accessibilityLabel(usage.fullSummary())
    }
}

extension MonthlyUsage {
    /// The total in compact form, such as "48.2K tokens this month".
    func compactSummary(locale: Locale = .autoupdatingCurrent) -> String {
        let total = tokens.total.formatted(
            .number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
        return "\(total) \(tokenWord) this month"
    }

    /// The exact total, such as "48,234 tokens this month".
    func fullSummary(locale: Locale = .autoupdatingCurrent) -> String {
        "\(tokens.total.formatted(.number.locale(locale))) \(tokenWord) this month"
    }

    /// One line per kind of token, then the request count.
    func breakdown(locale: Locale = .autoupdatingCurrent) -> String {
        rows.map { "\($0.label): \($0.value.formatted(.number.locale(locale)))" }
            .joined(separator: "\n")
    }

    /// The parts of the total and the request count, in display order.
    var rows: [(label: String, value: Int)] {
        [
            ("Input", tokens.input),
            ("Output", tokens.output),
            ("Cache write", tokens.cacheCreation),
            ("Cache read", tokens.cacheRead),
            ("Requests", requests),
        ]
    }

    private var tokenWord: String { tokens.total == 1 ? "token" : "tokens" }
}
