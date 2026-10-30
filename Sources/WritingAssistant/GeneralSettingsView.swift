import SwiftUI
import WritingAssistantCore

/// Settings tab for the learning summary and this month's tokens and cost.
struct GeneralSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show English learning summary", isOn: $model.includesLearningSummary)
                    Text("Turn it off for faster replies that use fewer tokens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Total tokens") {
                    Text(model.monthlyUsage.tokens.total.formatted())
                }
                LabeledContent("Estimated cost") {
                    Text(model.monthlyUsage.formattedCost(fractionDigits: 4))
                }
                ForEach(model.monthlyUsage.rows, id: \.label) { row in
                    LabeledContent(row.label) {
                        Text(row.value.formatted())
                    }
                }
            } header: {
                Text("This month")
            } footer: {
                Text(
                    "At API list prices, as reported by Claude Code. Your Claude subscription "
                        + "isn't charged per token."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshMonthlyUsage() }
    }
}
