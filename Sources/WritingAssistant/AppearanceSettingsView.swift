import AppKit
import SwiftUI

/// Settings tab for choosing a preset palette and overriding its colours.
struct AppearanceSettingsView: View {
    let settings: ThemeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PresetPicker(settings: settings)
                .padding([.horizontal, .top], 20)
            Form {
                Section("Colours") {
                    ForEach(ThemeToken.allCases, id: \.self) { token in
                        TokenColorRow(settings: settings, token: token)
                    }
                }
                Section {
                    HStack {
                        Spacer()
                        Button("Reset to Preset") { settings.resetToPreset() }
                            .disabled(!settings.isCustomized)
                            .accessibilityHint("Drops your custom colours")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A binding that shows `token`'s colour for `appearance` and stores picked colours as
    /// overrides. Picking the colour already shown changes nothing.
    static func colorBinding(
        settings: ThemeSettings, token: ThemeToken, appearance: ThemeAppearance
    ) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: settings.palette[token][appearance])) },
            set: { color in
                guard let hex = NSColor(color).hexValue,
                    hex != settings.palette[token][appearance]
                else { return }
                settings.setColor(hex, for: token, appearance: appearance)
            }
        )
    }
}

private struct PresetPicker: View {
    let settings: ThemeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(ThemePreset.allCases, id: \.self) { preset in
                    PresetCard(preset: preset, isSelected: preset == settings.preset) {
                        settings.select(preset)
                    }
                }
            }
            Text("Choosing a preset resets your custom colours.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PresetCard: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var appearance: ThemeAppearance { colorScheme == .dark ? .dark : .light }

    private func color(_ token: ThemeToken) -> Color {
        Color(nsColor: NSColor(hex: preset.palette[token][appearance]))
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(preset.displayName)
                    .font(.headline)
                    .foregroundStyle(color(.ink))
                HStack(spacing: 4) {
                    ForEach(ThemeToken.allCases, id: \.self) { token in
                        Circle()
                            .fill(color(token))
                            .overlay(Circle().strokeBorder(color(.rule)))
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color(.paper), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? color(.ink) : color(.rule), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Uses this palette and resets your custom colours")
    }
}

private struct TokenColorRow: View {
    let settings: ThemeSettings
    let token: ThemeToken

    var body: some View {
        LabeledContent(token.label) {
            HStack(spacing: 16) {
                picker("Light", appearance: .light)
                picker("Dark", appearance: .dark)
            }
        }
    }

    private func picker(_ title: String, appearance: ThemeAppearance) -> some View {
        ColorPicker(
            title,
            selection: AppearanceSettingsView.colorBinding(
                settings: settings, token: token, appearance: appearance),
            supportsOpacity: false
        )
        .accessibilityLabel("\(token.label), \(title.lowercased()) appearance")
    }
}
