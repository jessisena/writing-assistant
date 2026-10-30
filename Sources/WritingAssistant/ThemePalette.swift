import AppKit
import SwiftUI
import WritingAssistantCore
import os

/// One of the app's seven colour roles.
enum ThemeToken: String, Codable, CaseIterable, Sendable {
    /// App tint in Work mode: the Polish button, selected chips, the focus edge, links and
    /// vocabulary terms.
    case ink
    /// App tint in Personal mode, in place of `ink`, so the window shows which mode it is in.
    case personalInk
    /// Background of the writing sheet and the result cards.
    case paper
    /// Window background behind the sheet.
    case desk
    /// Hairline dividers and the border of the sheet and the cards.
    case rule
    /// Removed text in the diff, and the tint behind it at 12%. Also the length meter's warning.
    case redPencil
    /// Added text in the diff, and the tint behind it at 14%.
    case marginGreen

    /// Name shown in Settings.
    var label: String {
        switch self {
        case .ink: "Work accent"
        case .personalInk: "Personal accent"
        case .paper: "Sheet"
        case .desk: "Background"
        case .rule: "Dividers"
        case .redPencil: "Removed text"
        case .marginGreen: "Added text"
        }
    }
}

/// Which appearance a colour value is for.
enum ThemeAppearance: String, Codable, CaseIterable, Sendable {
    case light
    case dark
}

/// A token's `0xRRGGBB` value in the light and the dark appearance.
struct ThemeColor: Codable, Hashable, Sendable {
    var light: UInt32
    var dark: UInt32

    subscript(appearance: ThemeAppearance) -> UInt32 {
        get { appearance == .light ? light : dark }
        set {
            switch appearance {
            case .light: light = newValue
            case .dark: dark = newValue
            }
        }
    }
}

/// A full set of token colours. Each colour follows the light or dark appearance of the view
/// it is drawn in.
struct ThemePalette: Equatable, Sendable {
    var colors: [ThemeToken: ThemeColor]

    /// The value for `token`. Every preset defines all tokens, so a missing one is a bug.
    subscript(token: ThemeToken) -> ThemeColor {
        guard let color = colors[token] else {
            preconditionFailure("ThemePalette has no colour for \(token)")
        }
        return color
    }

    func color(_ token: ThemeToken) -> Color {
        let value = self[token]
        return Self.cache.withLock { cache in
            if let color = cache[value] { return color }
            let nsColor = NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? value.dark : value.light)
            }
            let color = Color(nsColor: nsColor)
            if cache.count >= Self.cacheLimit { cache.removeAll() }
            cache[value] = color
            return color
        }
    }

    /// One `Color` per value. Each dynamic `NSColor` is a distinct object, so without this two
    /// colours for the same token compare unequal and SwiftUI sees the tint change on every body.
    /// Dragging in the colour panel makes a new value per step; starting over past this bound
    /// keeps the cache small without tracking use.
    private static let cacheLimit = 256
    private static let cache = OSAllocatedUnfairLock(initialState: [ThemeColor: Color]())

    /// This palette with `mode`'s accent as `ink`, which every view tints with.
    func forMode(_ mode: Mode) -> ThemePalette {
        guard mode == .personal else { return self }
        var palette = self
        palette.colors[.ink] = self[.personalInk]
        return palette
    }

    var ink: Color { color(.ink) }
    var paper: Color { color(.paper) }
    var desk: Color { color(.desk) }
    var rule: Color { color(.rule) }
    var redPencil: Color { color(.redPencil) }
    var marginGreen: Color { color(.marginGreen) }
}

/// The palettes offered in Settings. Custom colours are stored as overrides on top of one.
enum ThemePreset: String, Codable, CaseIterable, Sendable {
    /// Blue-black ink, a proofreader's red pencil and a green margin pen on paper and a desk.
    case writingDesk
    /// Deep teal on cream, navy in the dark.
    case lagoon
    /// Brown ink on warm paper.
    case sepia

    var displayName: String {
        switch self {
        case .writingDesk: "Writing Desk"
        case .lagoon: "Lagoon"
        case .sepia: "Sepia"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .writingDesk:
            ThemePalette(colors: [
                .ink: ThemeColor(light: 0x33_378A, dark: 0xA9_ADF2),
                .personalInk: ThemeColor(light: 0x8A_3A6E, dark: 0xF0_A6D2),
                .paper: ThemeColor(light: 0xFD_FDFC, dark: 0x1F_2024),
                .desk: ThemeColor(light: 0xED_EFF3, dark: 0x14_1519),
                .rule: ThemeColor(light: 0xD9_DCE3, dark: 0x34_363D),
                .redPencil: ThemeColor(light: 0xB3_263E, dark: 0xFF_8597),
                .marginGreen: ThemeColor(light: 0x1D_7A52, dark: 0x63_D6A3),
            ])
        case .lagoon:
            ThemePalette(colors: [
                .ink: ThemeColor(light: 0x02_5F67, dark: 0x6F_CFC6),
                .personalInk: ThemeColor(light: 0xA3_4A1F, dark: 0xF5_B183),
                .paper: ThemeColor(light: 0xF7_F6F2, dark: 0x0B_2A45),
                .desk: ThemeColor(light: 0xE4_E8EA, dark: 0x04_1F35),
                .rule: ThemeColor(light: 0xBC_C5CC, dark: 0x24_435C),
                .redPencil: ThemeColor(light: 0xB8_463A, dark: 0xFF_8F80),
                .marginGreen: ThemeColor(light: 0x2F_9D94, dark: 0x63_D6C8),
            ])
        case .sepia:
            ThemePalette(colors: [
                .ink: ThemeColor(light: 0x8A_4B1F, dark: 0xE8_B07F),
                .personalInk: ThemeColor(light: 0x2F_6B4F, dark: 0x8F_D4AE),
                .paper: ThemeColor(light: 0xFB_F6EC, dark: 0x2A_241D),
                .desk: ThemeColor(light: 0xEF_E6D6, dark: 0x1C_1813),
                .rule: ThemeColor(light: 0xDC_CFB8, dark: 0x43_3A2E),
                .redPencil: ThemeColor(light: 0xA8_322A, dark: 0xFF_8C7A),
                .marginGreen: ThemeColor(light: 0x4D_7A2A, dark: 0x9C_D67A),
            ])
        }
    }
}

// A plain EnvironmentKey because `@Entry` needs the SwiftUI macro plugin, which ships with Xcode
// and not with the Command Line Tools this project builds with.
private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemePreset.writingDesk.palette
}

extension EnvironmentValues {
    /// The palette views draw with. Set from `ThemeSettings` on each scene.
    var theme: ThemePalette {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
