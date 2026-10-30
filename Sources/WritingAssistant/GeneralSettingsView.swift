import SwiftUI
import WritingAssistantCore

/// Settings tab for each mode's channels, language and learning summary, and this month's tokens
/// and cost.
struct GeneralSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            ModeSettingsSection(settings: model.modes, initialMode: model.mode)
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

/// One mode's settings at a time, picked with a segmented control that starts on the current
/// mode.
private struct ModeSettingsSection: View {
    let settings: ModeSettings
    @State private var mode: Mode

    init(settings: ModeSettings, initialMode: Mode) {
        self.settings = settings
        _mode = State(initialValue: initialMode)
    }

    private var profile: ModeProfile { settings[mode] }

    var body: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Write the result in", selection: outputLanguage) {
                ForEach(OutputLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show English learning summary", isOn: learningSummary)
                Text(
                    "Only for text you wrote in English. Turn it off for faster replies that use "
                        + "fewer tokens."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            ChannelVisibilityGrid(settings: settings, mode: mode)
        } header: {
            Text("Modes")
        } footer: {
            Text("Switch modes with the toolbar control or ⌘⇧M. Each mode remembers its channel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var outputLanguage: Binding<OutputLanguage> {
        Binding(
            get: { profile.outputLanguage },
            set: { settings.setOutputLanguage($0, for: mode) })
    }

    private var learningSummary: Binding<Bool> {
        Binding(
            get: { profile.learningSummary },
            set: { settings.setLearningSummary($0, for: mode) })
    }
}

/// A checkbox per channel. The last visible channel can't be unchecked.
private struct ChannelVisibilityGrid: View {
    let settings: ModeSettings
    let mode: Mode

    private let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Channels")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Channel.allCases) { channel in
                    toggle(for: channel)
                }
            }
            Text("A mode needs at least one channel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toggle(for channel: Channel) -> some View {
        let profile = settings[mode]
        let isOnlyVisible = profile.visibleChannels == [channel]
        return Toggle(
            channel.shortName,
            isOn: Binding(
                get: { settings[mode].isVisible(channel) },
                set: { settings.setVisible($0, for: channel, in: mode) })
        )
        .toggleStyle(.checkbox)
        .disabled(isOnlyVisible)
        .help(isOnlyVisible ? "A mode needs at least one channel." : channel.displayName)
    }
}
