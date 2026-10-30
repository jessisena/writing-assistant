import WritingAssistantCore

extension AppModel {
    /// The mode requests run in. Change it with `switchMode(to:)`.
    var mode: Mode { modes.current }

    /// The channel to write for: the current mode's last channel, or its first visible channel
    /// when that one was hidden. Setting it remembers the channel for the current mode.
    var channel: Channel {
        get { modes.profile.channel }
        set { modes.selectChannel(newValue) }
    }

    /// The current mode's channels with a chip, in chip order.
    var visibleChannels: [Channel] { modes.profile.visibleChannels }

    /// Whether a polish in the current mode asks for the English learning summary.
    var includesLearningSummary: Bool { modes.profile.learningSummary }

    /// What a polish started now asks for.
    var polishOptions: PolishOptions {
        let profile = modes.profile
        return PolishOptions(
            mode: mode, outputLanguage: profile.outputLanguage,
            includesLearningSummary: profile.learningSummary)
    }

    /// Whether the mode can be switched now: not while a request runs, so the result on screen
    /// always matches the mode shown (its summary card, its channel chips).
    var canSwitchMode: Bool { !isLoading }

    /// Makes `mode` current. Instant: nothing is sent and the screen keeps its text. Ignored
    /// while a request is running.
    func switchMode(to mode: Mode) {
        guard canSwitchMode else { return }
        modes.select(mode)
    }

    /// Switches to the other mode (⌘⇧M). Ignored while a request is running.
    func toggleMode() {
        switchMode(to: mode.toggled)
    }

    /// The history entries made in `mode`, newest first; every entry when `mode` is nil.
    func historyEntries(in mode: Mode?) -> [HistoryEntry] {
        guard let mode else { return history }
        return history.filter { $0.mode == mode }
    }
}
