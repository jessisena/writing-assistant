import Foundation
import Testing
import WritingAssistantCore

@testable import WritingAssistant

@MainActor
@Suite struct ModeSettingsTests {
    private let defaults = TestDefaults.make()

    private func stored(_ json: String) -> ModeSettings {
        defaults.set(json, forKey: ModeSettings.defaultsKey)
        return ModeSettings(defaults: defaults)
    }

    @Test func freshInstallStartsInWorkWithEachModesDefaults() {
        let settings = ModeSettings(defaults: defaults)

        #expect(settings.current == .work)
        #expect(
            settings[.work].visibleChannels == [
                .slack, .slackInformal, .email, .talkingPoints, .aiPrompt, .formal, .proofread,
            ])
        #expect(settings[.work].channel == .slack)
        #expect(settings[.work].outputLanguage == .english)
        #expect(settings[.work].learningSummary)
        #expect(
            settings[.personal].visibleChannels == [.personalMessage, .email, .proofread, .other])
        #expect(settings[.personal].channel == .personalMessage)
        #expect(settings[.personal].outputLanguage == .sameAsInput)
        #expect(!settings[.personal].learningSummary)
        #expect(defaults.string(forKey: ModeSettings.defaultsKey) == nil)
    }

    @Test func everyChangeSurvivesANewInstance() {
        let settings = ModeSettings(defaults: defaults)
        settings.select(.personal)
        settings.selectChannel(.other)
        settings.setVisible(false, for: .email, in: .personal)
        settings.setOutputLanguage(.english, for: .personal)
        settings.setLearningSummary(true, for: .personal)
        settings.setLearningSummary(false, for: .work)

        let relaunched = ModeSettings(defaults: defaults)

        #expect(relaunched.current == .personal)
        #expect(relaunched[.personal] == settings[.personal])
        #expect(relaunched[.personal].channel == .other)
        #expect(!relaunched[.personal].isVisible(.email))
        #expect(relaunched[.personal].outputLanguage == .english)
        #expect(relaunched[.personal].learningSummary)
        #expect(!relaunched[.work].learningSummary)
    }

    @Test func savesReadableJSON() throws {
        let settings = ModeSettings(defaults: defaults)
        settings.select(.personal)

        let json = try #require(defaults.string(forKey: ModeSettings.defaultsKey))

        #expect(json.contains(#""current":"personal""#))
        #expect(json.contains(#""outputLanguage":"sameAsInput""#))
        #expect(json.contains(#""lastChannel":"personal_message""#))
        #expect(
            json.contains(#""visibleChannels":["personal_message","email","proofread","other"]"#))
    }

    @Test func eachModeRemembersItsOwnChannel() {
        let settings = ModeSettings(defaults: defaults)
        settings.selectChannel(.aiPrompt)
        settings.select(.personal)
        settings.selectChannel(.proofread)

        settings.select(.work)

        #expect(settings.profile.channel == .aiPrompt)
        #expect(settings[.personal].channel == .proofread)
    }

    @Test(arguments: ["{not json", "[]", #"{"work": "slack"}"#, ""])
    func undecodableValueLoadsTheDefaults(json: String) {
        let settings = stored(json)

        #expect(settings.current == .work)
        #expect(settings[.work] == .defaults(for: .work))
        #expect(settings[.personal] == .defaults(for: .personal))
    }

    @Test func missingKeysTakeThatModesDefaults() {
        let settings = stored(#"{"current":"personal","personal":{"learningSummary":true}}"#)

        #expect(settings.current == .personal)
        #expect(settings[.personal].learningSummary)
        #expect(settings[.personal].outputLanguage == .sameAsInput)
        #expect(
            settings[.personal].visibleChannels
                == ModeProfile.defaults(for: .personal).visibleChannels)
        #expect(settings[.work] == .defaults(for: .work))
    }

    @Test func unknownValuesAreDroppedOrFallBack() {
        let settings = stored(
            #"{"current":"family","work":{"visibleChannels":["telegram","email","slack"],"#
                + #""lastChannel":"fax","outputLanguage":"klingon"}}"#)

        #expect(settings.current == .work)
        #expect(settings[.work].visibleChannels == [.email, .slack])
        #expect(settings[.work].lastChannel == .slack)
        #expect(settings[.work].outputLanguage == .english)
    }

    @Test(arguments: [#"[]"#, #"["telegram"]"#])
    func emptyChannelListTakesTheDefaultList(channels: String) {
        let settings = stored(#"{"work":{"visibleChannels":"# + channels + "}}")

        #expect(
            settings[.work].visibleChannels == ModeProfile.defaults(for: .work).visibleChannels)
    }

    @Test func hiddenLastChannelFallsBackToTheFirstVisibleOne() {
        let settings = ModeSettings(defaults: defaults)
        settings.selectChannel(.aiPrompt)

        settings.setVisible(false, for: .aiPrompt, in: .work)

        #expect(settings.profile.lastChannel == .aiPrompt)
        #expect(settings.profile.channel == .slack)
        settings.setVisible(true, for: .aiPrompt, in: .work)
        #expect(settings.profile.channel == .aiPrompt)
    }

    @Test func theLastVisibleChannelCannotBeHidden() {
        let settings = ModeSettings(defaults: defaults)
        for channel in [Channel.personalMessage, .email, .proofread] {
            #expect(settings.setVisible(false, for: channel, in: .personal))
        }

        #expect(!settings.setVisible(false, for: .other, in: .personal))

        #expect(settings[.personal].visibleChannels == [.other])
        #expect(ModeSettings(defaults: defaults)[.personal].visibleChannels == [.other])
    }

    @Test func aShownChannelBecomesTheLastChip() {
        let settings = ModeSettings(defaults: defaults)

        settings.setVisible(true, for: .slack, in: .personal)
        settings.setVisible(true, for: .email, in: .personal)

        #expect(
            settings[.personal].visibleChannels == [
                .personalMessage, .email, .proofread, .other, .slack,
            ])
    }

    @Test func duplicateStoredChannelsAreDropped() {
        let settings = stored(#"{"work":{"visibleChannels":["email","slack","email"]}}"#)

        #expect(settings[.work].visibleChannels == [.email, .slack])
    }

    @Test func separateSuitesDoNotShareModes() {
        ModeSettings(defaults: defaults).select(.personal)

        #expect(ModeSettings(defaults: TestDefaults.make()).current == .work)
    }
}
