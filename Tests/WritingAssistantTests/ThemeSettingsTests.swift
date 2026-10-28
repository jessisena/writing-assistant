import Foundation
import Testing

@testable import WritingAssistant

@MainActor
@Suite struct ThemeSettingsTests {
    private func storedJSON(in defaults: UserDefaults) throws -> [String: Any] {
        let string = try #require(defaults.string(forKey: ThemeSettings.defaultsKey))
        let object = try JSONSerialization.jsonObject(with: Data(string.utf8))
        return try #require(object as? [String: Any])
    }

    private func expectDefaultTheme(_ settings: ThemeSettings) {
        #expect(settings.preset == .writingDesk)
        #expect(settings.overrides.isEmpty)
        #expect(settings.palette == ThemePreset.writingDesk.palette)
    }

    @Test func defaultIsWritingDeskWithoutOverrides() {
        let settings = ThemeSettings(defaults: TestDefaults.make())

        expectDefaultTheme(settings)
        #expect(!settings.isCustomized)
    }

    @Test func presetAndOverridesSurviveANewInstance() {
        let defaults = TestDefaults.make()
        let settings = ThemeSettings(defaults: defaults)
        settings.select(.lagoon)
        settings.setColor(0x12_3456, for: .ink, appearance: .light)
        settings.setColor(0xAB_CDEF, for: .redPencil, appearance: .dark)

        let relaunched = ThemeSettings(defaults: defaults)

        #expect(relaunched.preset == .lagoon)
        #expect(relaunched.overrides == settings.overrides)
        #expect(relaunched.palette == settings.palette)
    }

    @Test func resetSurvivesANewInstance() {
        let defaults = TestDefaults.make()
        let settings = ThemeSettings(defaults: defaults)
        settings.select(.sepia)
        settings.setColor(0x12_3456, for: .ink, appearance: .light)
        settings.resetToPreset()

        let relaunched = ThemeSettings(defaults: defaults)

        #expect(relaunched.preset == .sepia)
        #expect(relaunched.overrides.isEmpty)
    }

    @Test func handWrittenJSONLoadsWithLowercaseHex() {
        let defaults = TestDefaults.make()
        defaults.set(
            ##"{"preset":"lagoon","overrides":{"paper":{"light":"#abcdef","dark":"#0A0B0C"}}}"##,
            forKey: ThemeSettings.defaultsKey)

        let settings = ThemeSettings(defaults: defaults)

        #expect(settings.preset == .lagoon)
        #expect(settings.overrides == [.paper: ThemeColor(light: 0xAB_CDEF, dark: 0x0A_0B0C)])
    }

    @Test func presetWithoutOverridesLoads() {
        let defaults = TestDefaults.make()
        defaults.set(##"{"preset":"sepia"}"##, forKey: ThemeSettings.defaultsKey)

        let settings = ThemeSettings(defaults: defaults)

        #expect(settings.preset == .sepia)
        #expect(settings.overrides.isEmpty)
    }

    @Test(arguments: [
        "not json",
        ##"{"overrides":{}}"##,
        ##"{"preset":"neon","overrides":{}}"##,
        ##"{"preset":"lagoon","overrides":{"chrome":{"light":"#000000","dark":"#FFFFFF"}}}"##,
        ##"{"preset":"lagoon","overrides":{"ink":{"light":"#12345","dark":"#FFFFFF"}}}"##,
        ##"{"preset":"lagoon","overrides":{"ink":{"light":"123456","dark":"#FFFFFF"}}}"##,
        ##"{"preset":"lagoon","overrides":{"ink":{"light":"#GGGGGG","dark":"#FFFFFF"}}}"##,
        ##"{"preset":"lagoon","overrides":{"ink":{"light":"#+12345","dark":"#FFFFFF"}}}"##,
    ])
    func invalidSavedThemeFallsBackToWritingDesk(json: String) {
        let defaults = TestDefaults.make()
        defaults.set(json, forKey: ThemeSettings.defaultsKey)

        expectDefaultTheme(ThemeSettings(defaults: defaults))
    }

    @Test func savedThemeThatIsNotAStringFallsBackToWritingDesk() {
        let defaults = TestDefaults.make()
        defaults.set(42, forKey: ThemeSettings.defaultsKey)

        expectDefaultTheme(ThemeSettings(defaults: defaults))
    }

    @Test func selectClearsOverrides() {
        let settings = ThemeSettings(defaults: TestDefaults.make())
        settings.setColor(0x12_3456, for: .ink, appearance: .light)

        settings.select(.sepia)

        #expect(settings.preset == .sepia)
        #expect(settings.overrides.isEmpty)
        #expect(settings.palette == ThemePreset.sepia.palette)
    }

    @Test func resetToPresetClearsOverridesAndKeepsPreset() {
        let settings = ThemeSettings(defaults: TestDefaults.make())
        settings.select(.lagoon)
        settings.setColor(0x12_3456, for: .ink, appearance: .light)

        settings.resetToPreset()

        #expect(settings.preset == .lagoon)
        #expect(settings.overrides.isEmpty)
        #expect(!settings.isCustomized)
    }

    @Test func isCustomizedFollowsWhetherAnyColourDiffersFromThePreset() {
        let settings = ThemeSettings(defaults: TestDefaults.make())
        let presetInk = ThemePreset.writingDesk.palette[.ink].light

        settings.setColor(0x12_3456, for: .ink, appearance: .light)
        #expect(settings.isCustomized)

        settings.setColor(presetInk, for: .ink, appearance: .light)
        #expect(!settings.isCustomized)
    }

    @Test func overridingLightKeepsThePresetDarkValue() {
        let settings = ThemeSettings(defaults: TestDefaults.make())
        let preset = ThemePreset.writingDesk.palette[.desk]

        settings.setColor(0x12_3456, for: .desk, appearance: .light)

        #expect(settings.palette[.desk] == ThemeColor(light: 0x12_3456, dark: preset.dark))
    }

    @Test func storedValueIsTheDocumentedJSONShape() throws {
        let defaults = TestDefaults.make()
        let settings = ThemeSettings(defaults: defaults)
        settings.select(.lagoon)
        settings.setColor(0x0A_BC0D, for: .marginGreen, appearance: .dark)

        let json = try storedJSON(in: defaults)

        #expect(Set(json.keys) == ["preset", "overrides"])
        #expect(json["preset"] as? String == "lagoon")
        let overrides = try #require(json["overrides"] as? [String: [String: String]])
        #expect(overrides == ["marginGreen": ["light": "#2F9D94", "dark": "#0ABC0D"]])
    }

    @Test func storedValueAfterSelectHasNoOverrides() throws {
        let defaults = TestDefaults.make()
        ThemeSettings(defaults: defaults).select(.sepia)

        let json = try storedJSON(in: defaults)

        #expect(json["preset"] as? String == "sepia")
        #expect((json["overrides"] as? [String: Any])?.isEmpty == true)
    }
}
