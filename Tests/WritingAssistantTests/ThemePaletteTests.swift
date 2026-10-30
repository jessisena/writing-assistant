import AppKit
import SwiftUI
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct ThemePaletteTests {
    @Test(arguments: ThemePreset.allCases)
    func everyPresetDefinesEveryToken(preset: ThemePreset) {
        let tokens = Set(preset.palette.colors.keys)

        #expect(tokens == Set(ThemeToken.allCases))
    }

    @Test(arguments: ThemePreset.allCases)
    func colorResolvesToTheLightHexInTheLightAppearance(preset: ThemePreset) {
        let palette = preset.palette
        for token in ThemeToken.allCases {
            #expect(palette.color(token).hex(in: .aqua) == palette[token].light, "\(token)")
        }
    }

    @Test(arguments: ThemePreset.allCases)
    func colorResolvesToTheDarkHexInTheDarkAppearance(preset: ThemePreset) {
        let palette = preset.palette
        for token in ThemeToken.allCases {
            #expect(palette.color(token).hex(in: .darkAqua) == palette[token].dark, "\(token)")
        }
    }

    @Test func colorFollowsACustomValue() {
        var palette = ThemePreset.writingDesk.palette
        palette.colors[.ink] = ThemeColor(light: 0x00_0000, dark: 0xFF_FFFF)

        #expect(palette.ink.hex(in: .aqua) == 0x00_0000)
        #expect(palette.ink.hex(in: .darkAqua) == 0xFF_FFFF)
    }

    @Test(arguments: ThemePreset.allCases)
    func personalModeTintsWithThePersonalAccent(preset: ThemePreset) {
        let palette = preset.palette

        #expect(palette.forMode(.work) == palette)
        #expect(palette.forMode(.personal)[.ink] == palette[.personalInk])
        #expect(palette[.personalInk] != palette[.ink])
        #expect(palette.forMode(.personal)[.paper] == palette[.paper])
    }

    @Test func sameValueGivesAnEqualColor() {
        let lagoon = ThemePreset.lagoon.palette
        var custom = ThemePreset.writingDesk.palette
        custom.colors[.ink] = lagoon[.ink]

        #expect(lagoon.ink == lagoon.ink)
        #expect(custom.ink == lagoon.ink)
        #expect(lagoon.ink != ThemePreset.writingDesk.palette.ink)
    }
}

extension Color {
    /// The colour in sRGB as drawn under the named appearance, to check what a dynamic palette
    /// colour actually draws.
    @MainActor
    func resolved(in appearanceName: NSAppearance.Name) -> NSColor? {
        guard let appearance = NSAppearance(named: appearanceName) else { return nil }
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(self).usingColorSpace(.sRGB)
        }
        return resolved
    }

    /// The colour's `0xRRGGBB` value in sRGB as drawn under the named appearance, ignoring alpha.
    @MainActor
    func hex(in appearanceName: NSAppearance.Name) -> UInt32? {
        guard let resolved = resolved(in: appearanceName) else { return nil }
        let red = UInt32((resolved.redComponent * 255).rounded())
        let green = UInt32((resolved.greenComponent * 255).rounded())
        let blue = UInt32((resolved.blueComponent * 255).rounded())
        return red << 16 | green << 8 | blue
    }
}
