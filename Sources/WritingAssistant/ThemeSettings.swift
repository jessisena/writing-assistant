import Foundation
import Observation
import os

/// The chosen preset and the user's custom colours on top of it.
///
/// Saved under `defaultsKey` as a JSON string, so `defaults write` or an agent can set a theme:
/// `{"preset":"lagoon","overrides":{"ink":{"light":"#025F67","dark":"#6FCFC6"}}}`.
/// `preset` is a `ThemePreset` raw value, override keys are `ThemeToken` raw values and colours
/// are `#RRGGBB`; `overrides` may be left out. A value that doesn't parse loads as Writing Desk
/// without overrides.
@MainActor @Observable final class ThemeSettings {
    static let defaultsKey = "theme"

    private(set) var preset: ThemePreset
    private(set) var overrides: [ThemeToken: ThemeColor]

    @ObservationIgnored private let defaults: UserDefaults

    private static let logger = Logger(subsystem: "local.writing-assistant", category: "theme")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preset = .writingDesk
        overrides = [:]
        load()
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
        save()
    }

    /// Sets `token`'s colour for one appearance, keeping the other appearance's value.
    func setColor(_ hex: UInt32, for token: ThemeToken, appearance: ThemeAppearance) {
        var color = palette[token]
        color[appearance] = hex
        overrides[token] = color
        save()
    }

    func resetToPreset() {
        overrides = [:]
        save()
    }

    private func load() {
        guard let json = defaults.string(forKey: Self.defaultsKey) else { return }
        do {
            let stored = try JSONDecoder().decode(StoredTheme.self, from: Data(json.utf8))
            (preset, overrides) = try stored.resolved()
        } catch {
            Self.logger.error(
                "Ignoring saved theme \(json, privacy: .public): \(error, privacy: .public)")
        }
    }

    private func save() {
        let stored = StoredTheme(preset: preset, overrides: overrides)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(stored)
            defaults.set(String(decoding: data, as: UTF8.self), forKey: Self.defaultsKey)
        } catch {
            Self.logger.error("Couldn't save theme: \(error, privacy: .public)")
        }
    }
}

/// The JSON shape saved in UserDefaults. String keys, so the overrides encode as an object.
private struct StoredTheme: Codable {
    struct Color: Codable {
        var light: String
        var dark: String
    }

    enum InvalidValue: Error, CustomStringConvertible {
        case preset(String)
        case token(String)
        case hex(String)

        var description: String {
            switch self {
            case .preset(let name): "unknown preset \"\(name)\""
            case .token(let name): "unknown token \"\(name)\""
            case .hex(let value): "\"\(value)\" is not a #RRGGBB colour"
            }
        }
    }

    var preset: String
    /// Optional on read, so `{"preset":"sepia"}` is enough to pick a preset.
    var overrides: [String: Color]?

    init(preset: ThemePreset, overrides: [ThemeToken: ThemeColor]) {
        self.preset = preset.rawValue
        self.overrides = Dictionary(
            uniqueKeysWithValues: overrides.map { token, color in
                (token.rawValue, Color(light: Self.hex(color.light), dark: Self.hex(color.dark)))
            })
    }

    func resolved() throws -> (ThemePreset, [ThemeToken: ThemeColor]) {
        guard let preset = ThemePreset(rawValue: preset) else { throw InvalidValue.preset(preset) }
        var result: [ThemeToken: ThemeColor] = [:]
        for (name, color) in overrides ?? [:] {
            guard let token = ThemeToken(rawValue: name) else { throw InvalidValue.token(name) }
            result[token] = try ThemeColor(
                light: Self.value(color.light), dark: Self.value(color.dark))
        }
        return (preset, result)
    }

    private static func hex(_ value: UInt32) -> String {
        "#" + String(format: "%06X", value & 0xFF_FFFF)
    }

    private static func value(_ hex: String) throws -> UInt32 {
        let digits = hex.dropFirst()
        guard hex.first == "#", digits.count == 6, digits.allSatisfy(\.isHexDigit),
            let value = UInt32(digits, radix: 16)
        else { throw InvalidValue.hex(hex) }
        return value
    }
}
