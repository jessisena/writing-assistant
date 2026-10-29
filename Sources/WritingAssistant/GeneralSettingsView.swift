import SwiftUI
import WritingAssistantCore

/// Settings tab for the learning summary and this month's token usage.
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
            Section("This month") {
                LabeledContent("Total tokens") {
                    Text(model.monthlyUsage.tokens.total.formatted())
                }
                ForEach(model.monthlyUsage.rows, id: \.label) { row in
                    LabeledContent(row.label) {
                        Text(row.value.formatted())
                    }
                }
            }
            .monospacedDigit()
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
