import AppKit
import SwiftUI
import Testing

@testable import WritingAssistant

@Suite struct NSColorHexTests {
    private static let presetValues: [UInt32] = ThemePreset.allCases.flatMap { preset in
        ThemeToken.allCases.flatMap { token in
            [preset.palette[token].light, preset.palette[token].dark]
        }
    }

    @Test(arguments: [0x00_0000, 0xFF_FFFF, 0x80_8080, 0x01_02FE] + presetValues)
    func hexRoundTrips(hex: UInt32) {
        #expect(NSColor(hex: hex).hexValue == hex)
    }

    @Test func displayP3ColourConvertsToItsSRGBEquivalent() throws {
        let p3 = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)

        let hex = try #require(p3.hexValue)

        #expect(hex >> 16 == 0xFF)
        #expect(hex & 0xFF_FF == 0)
    }

    @Test func colourBackedBySwiftUIColorConverts() {
        let color = Color(nsColor: NSColor(hex: 0x33_378A))

        #expect(NSColor(color).hexValue == 0x33_378A)
    }

    @Test func greyscaleColourConverts() {
        #expect(NSColor(white: 1, alpha: 1).hexValue == 0xFF_FFFF)
    }

    @Test func alphaIsIgnored() {
        let translucent = NSColor(hex: 0x12_3456).withAlphaComponent(0.5)

        #expect(translucent.hexValue == 0x12_3456)
    }
}
