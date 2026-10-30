import Foundation
import Observation
import WritingAssistantCore
import os

/// One mode's settings.
struct ModeProfile: Equatable, Sendable {
    /// The channels with a chip, in chip order: the defaults' order, with channels shown later
    /// at the end. Never empty, no duplicates.
    private(set) var visibleChannels: [Channel]
    /// The channel picked last in this mode. It may since have been hidden; `channel` is then
    /// the first visible one.
    var lastChannel: Channel
    var outputLanguage: OutputLanguage
    var learningSummary: Bool

    init(
        visibleChannels: [Channel], lastChannel: Channel, outputLanguage: OutputLanguage,
        learningSummary: Bool
    ) {
        var unique: [Channel] = []
        for channel in visibleChannels where !unique.contains(channel) {
            unique.append(channel)
        }
        precondition(!unique.isEmpty, "A mode needs at least one visible channel")
        self.visibleChannels = unique
        self.lastChannel = lastChannel
        self.outputLanguage = outputLanguage
        self.learningSummary = learningSummary
    }

    /// What a fresh install starts with in `mode`.
    static func defaults(for mode: Mode) -> ModeProfile {
        switch mode {
        case .work:
            ModeProfile(
                visibleChannels: [
                    .slack, .slackInformal, .email, .talkingPoints, .aiPrompt, .formal, .proofread,
                ],
                lastChannel: .slack, outputLanguage: .english, learningSummary: true)
        case .personal:
            ModeProfile(
                visibleChannels: [.personalMessage, .email, .proofread, .other],
                lastChannel: .personalMessage, outputLanguage: .sameAsInput,
                learningSummary: false)
        }
    }

    /// The channel requests use: `lastChannel` while it is visible, else the first visible one.
    var channel: Channel {
        visibleChannels.contains(lastChannel) ? lastChannel : visibleChannels[0]
    }

    func isVisible(_ channel: Channel) -> Bool {
        visibleChannels.contains(channel)
    }

    /// Shows `channel` as the last chip, or hides it. Hiding the only visible channel is refused.
    ///
    /// - Returns: False when the change was refused.
    @discardableResult
    mutating func setVisible(_ visible: Bool, for channel: Channel) -> Bool {
        if visible {
            if !isVisible(channel) { visibleChannels.append(channel) }
            return true
        }
        guard visibleChannels != [channel] else { return false }
        visibleChannels.removeAll { $0 == channel }
        return true
    }
}

/// The current mode and both modes' settings.
///
/// Saved under `defaultsKey` as a JSON string, so `defaults write` or an agent can change it:
/// `{"current":"personal","work":{"visibleChannels":["slack","email"],"lastChannel":"slack",
/// "outputLanguage":"english","learningSummary":true},"personal":{…}}`. Mode and channel names
/// are `Mode` and `Channel` raw values, `outputLanguage` is `english` or `sameAsInput`. Every key
/// may be left out and takes that mode's default; unknown channel names are dropped, and an empty
/// channel list takes the default list. A value that doesn't parse loads as the defaults.
@MainActor @Observable final class ModeSettings {
    static let defaultsKey = "modes"

    private(set) var current: Mode
    private var profiles: [Mode: ModeProfile]

    @ObservationIgnored private let defaults: UserDefaults

    private static let logger = Logger(subsystem: "local.writing-assistant", category: "modes")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        current = .work
        profiles = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, .defaults(for: $0)) })
        load()
    }

    subscript(mode: Mode) -> ModeProfile {
        profiles[mode] ?? .defaults(for: mode)
    }

    /// The current mode's settings.
    var profile: ModeProfile { self[current] }

    func select(_ mode: Mode) {
        guard mode != current else { return }
        current = mode
        save()
    }

    /// Remembers `channel` as the current mode's last channel.
    func selectChannel(_ channel: Channel) {
        update(current) { $0.lastChannel = channel }
    }

    /// Shows or hides `channel` in `mode`. Hiding the mode's only visible channel is refused.
    ///
    /// - Returns: False when the change was refused.
    @discardableResult
    func setVisible(_ visible: Bool, for channel: Channel, in mode: Mode) -> Bool {
        var changed = true
        update(mode) { changed = $0.setVisible(visible, for: channel) }
        return changed
    }

    func setOutputLanguage(_ language: OutputLanguage, for mode: Mode) {
        update(mode) { $0.outputLanguage = language }
    }

    func setLearningSummary(_ isOn: Bool, for mode: Mode) {
        update(mode) { $0.learningSummary = isOn }
    }

    private func update(_ mode: Mode, _ change: (inout ModeProfile) -> Void) {
        var profile = self[mode]
        change(&profile)
        guard profile != self[mode] else { return }
        profiles[mode] = profile
        save()
    }

    private func load() {
        guard let json = defaults.string(forKey: Self.defaultsKey) else { return }
        do {
            let stored = try JSONDecoder().decode(StoredModes.self, from: Data(json.utf8))
            current = stored.current.flatMap(Mode.init(rawValue:)) ?? .work
            profiles[.work] = stored.work?.resolved(for: .work) ?? .defaults(for: .work)
            profiles[.personal] =
                stored.personal?.resolved(for: .personal) ?? .defaults(for: .personal)
        } catch {
            Self.logger.error(
                "Ignoring saved modes \(json, privacy: .public): \(error, privacy: .public)")
        }
    }

    private func save() {
        let stored = StoredModes(
            current: current.rawValue, work: StoredProfile(self[.work]),
            personal: StoredProfile(self[.personal]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(stored)
            defaults.set(String(decoding: data, as: UTF8.self), forKey: Self.defaultsKey)
        } catch {
            Self.logger.error("Couldn't save modes: \(error, privacy: .public)")
        }
    }
}

/// The JSON shape saved in UserDefaults. Every field is optional on read.
private struct StoredModes: Codable {
    var current: String?
    var work: StoredProfile?
    var personal: StoredProfile?
}

private struct StoredProfile: Codable {
    var visibleChannels: [String]?
    var lastChannel: String?
    var outputLanguage: String?
    var learningSummary: Bool?

    init(_ profile: ModeProfile) {
        visibleChannels = profile.visibleChannels.map(\.rawValue)
        lastChannel = profile.lastChannel.rawValue
        outputLanguage = profile.outputLanguage.rawValue
        learningSummary = profile.learningSummary
    }

    /// The stored values over `mode`'s defaults.
    func resolved(for mode: Mode) -> ModeProfile {
        let fallback = ModeProfile.defaults(for: mode)
        let channels = (visibleChannels ?? []).compactMap(Channel.init(rawValue:))
        return ModeProfile(
            visibleChannels: channels.isEmpty ? fallback.visibleChannels : channels,
            lastChannel: lastChannel.flatMap(Channel.init(rawValue:)) ?? fallback.lastChannel,
            outputLanguage: outputLanguage.flatMap(OutputLanguage.init(rawValue:))
                ?? fallback.outputLanguage,
            learningSummary: learningSummary ?? fallback.learningSummary)
    }
}
