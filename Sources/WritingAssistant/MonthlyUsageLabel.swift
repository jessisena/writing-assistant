import SwiftUI
import WritingAssistantCore

/// The month's token total and cost as one quiet toolbar line, with the breakdown in its tooltip.
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
    /// The total and cost in compact form, such as "48.2K tokens · $0.42 this month".
    func compactSummary(locale: Locale = .autoupdatingCurrent) -> String {
        let total = tokens.total.formatted(
            .number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
        return "\(total) \(tokenWord) · \(formattedCost(fractionDigits: 2, locale: locale)) "
            + "this month"
    }

    /// The exact total and the cost, such as "48,234 tokens, about $0.42 at API prices, this
    /// month".
    func fullSummary(locale: Locale = .autoupdatingCurrent) -> String {
        "\(tokens.total.formatted(.number.locale(locale))) \(tokenWord), about "
            + "\(formattedCost(fractionDigits: 2, locale: locale)) at API prices, this month"
    }

    /// One line per kind of token, then the request count and the cost.
    func breakdown(locale: Locale = .autoupdatingCurrent) -> String {
        let lines = rows.map { "\($0.label): \($0.value.formatted(.number.locale(locale)))" }
        let cost = "Cost at API prices: \(formattedCost(fractionDigits: 4, locale: locale))"
        return (lines + [cost]).joined(separator: "\n")
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

    /// `costUSD` in US dollars, such as "$0.42". A cost above zero but under the smallest step
    /// shows as "<$0.01" (or "<$0.0001"), so spending never reads as free.
    func formattedCost(fractionDigits: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: "USD", locale: locale)
            .precision(.fractionLength(fractionDigits))
        let smallestStep = pow(10, -Double(fractionDigits))
        if costUSD > 0, costUSD < smallestStep {
            return "<\(smallestStep.formatted(style))"
        }
        return costUSD.formatted(style)
    }

    private var tokenWord: String { tokens.total == 1 ? "token" : "tokens" }
}
