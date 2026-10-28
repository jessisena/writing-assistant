import Foundation
import Observation

/// The chosen preset and the user's custom colours on top of it.
@MainActor @Observable final class ThemeSettings {
    private(set) var preset: ThemePreset
    private(set) var overrides: [ThemeToken: ThemeColor]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preset = .writingDesk
        overrides = [:]
    }

    /// The preset's colours with the overrides applied.
    var palette: ThemePalette {
        var palette = preset.palette
        palette.colors.merge(overrides) { _, override in override }
        return palette
    }

    /// Whether any colour differs from the preset.
    var isCustomized: Bool {
        overrides.contains { token, color in preset.palette[token] != color }
    }

    /// Switches to `preset` and drops the custom colours.
    func select(_ preset: ThemePreset) {
        self.preset = preset
        overrides = [:]
    }

    /// Sets `token`'s colour for one appearance, keeping the other appearance's value.
    func setColor(_ hex: UInt32, for token: ThemeToken, appearance: ThemeAppearance) {
        var color = palette[token]
        color[appearance] = hex
        overrides[token] = color
    }

    func resetToPreset() {
        overrides = [:]
    }
}
