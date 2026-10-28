import AppKit
import SwiftUI
import Testing

@testable import WritingAssistant

@MainActor
@Suite struct AppearanceSettingsTests {
    @Test func bindingShowsTheCurrentColourForTheAppearance() {
        let settings = ThemeSettings(defaults: TestDefaults.make())
        let expected = settings.palette[.ink]

        let light = AppearanceSettingsView.colorBinding(
            settings: settings, token: .ink, appearance: .light)
        let dark = AppearanceSettingsView.colorBinding(
            settings: settings, token: .ink, appearance: .dark)

        #expect(NSColor(light.wrappedValue).hexValue == expected.light)
        #expect(NSColor(dark.wrappedValue).hexValue == expected.dark)
    }

    @Test func settingAColourStoresItForThatAppearanceOnly() {
        let settings = ThemeSettings(defaults: TestDefaults.make())
        let originalDark = settings.palette[.paper].dark
        let binding = AppearanceSettingsView.colorBinding(
            settings: settings, token: .paper, appearance: .light)

        binding.wrappedValue = Color(nsColor: NSColor(hex: 0x12_3456))

        #expect(settings.palette[.paper] == ThemeColor(light: 0x12_3456, dark: originalDark))
        #expect(settings.isCustomized)
    }

    @Test func settingTheUnchangedColourCreatesNoOverride() {
        let settings = ThemeSettings(defaults: TestDefaults.make())
        let binding = AppearanceSettingsView.colorBinding(
            settings: settings, token: .rule, appearance: .dark)

        binding.wrappedValue = binding.wrappedValue

        #expect(settings.overrides.isEmpty)
        #expect(!settings.isCustomized)
    }
}
