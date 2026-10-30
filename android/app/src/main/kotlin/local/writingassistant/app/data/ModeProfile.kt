package local.writingassistant.app.data

import local.writingassistant.core.Channel
import local.writingassistant.core.Mode
import local.writingassistant.core.OutputLanguage
import local.writingassistant.core.PolishOptions

/**
 * One mode's settings. Mirrors `ModeProfile` in `ModeSettings.swift`.
 *
 * @property visibleChannels The channels with a chip, in chip order; never empty and without
 *   duplicates.
 * @property lastChannel The channel picked last in this mode. It may since have been hidden;
 *   [channel] is then the first visible one.
 */
data class ModeProfile(
    val visibleChannels: List<Channel>,
    val lastChannel: Channel,
    val outputLanguage: OutputLanguage,
    val learningSummary: Boolean,
) {
    init {
        require(visibleChannels.isNotEmpty()) { "A mode needs at least one visible channel" }
        require(visibleChannels.distinct() == visibleChannels) { "Duplicate visible channels" }
    }

    /** The channel requests use: [lastChannel] while it is visible, else the first visible one. */
    val channel: Channel
        get() = lastChannel.takeIf { it in visibleChannels } ?: visibleChannels.first()

    /** Whether [channel] is the only visible one, so it can't be hidden. */
    fun isOnlyVisible(channel: Channel): Boolean = visibleChannels == listOf(channel)

    /**
     * [visibleChannels] with [channel] shown (appended at the end) or hidden; null when that
     * would hide the only visible channel.
     */
    fun withVisible(
        channel: Channel,
        visible: Boolean,
    ): ModeProfile? =
        when {
            visible && channel in visibleChannels -> this
            visible -> copy(visibleChannels = visibleChannels + channel)
            isOnlyVisible(channel) -> null
            else -> copy(visibleChannels = visibleChannels - channel)
        }

    companion object {
        /** What a fresh install starts with in [mode]. */
        fun defaults(mode: Mode): ModeProfile =
            when (mode) {
                Mode.WORK -> {
                    ModeProfile(
                        visibleChannels =
                            listOf(
                                Channel.SLACK,
                                Channel.SLACK_INFORMAL,
                                Channel.EMAIL,
                                Channel.TALKING_POINTS,
                                Channel.AI_PROMPT,
                                Channel.FORMAL,
                                Channel.PROOFREAD,
                            ),
                        lastChannel = Channel.SLACK,
                        outputLanguage = OutputLanguage.ENGLISH,
                        learningSummary = true,
                    )
                }

                Mode.PERSONAL -> {
                    ModeProfile(
                        visibleChannels =
                            listOf(
                                Channel.PERSONAL_MESSAGE,
                                Channel.EMAIL,
                                Channel.PROOFREAD,
                                Channel.OTHER,
                            ),
                        lastChannel = Channel.PERSONAL_MESSAGE,
                        outputLanguage = OutputLanguage.SAME_AS_INPUT,
                        learningSummary = false,
                    )
                }
            }
    }
}

/** The current mode and both modes' settings, as last stored. */
data class ModeSettings(
    val current: Mode = Mode.WORK,
    val work: ModeProfile = ModeProfile.defaults(Mode.WORK),
    val personal: ModeProfile = ModeProfile.defaults(Mode.PERSONAL),
) {
    operator fun get(mode: Mode): ModeProfile =
        when (mode) {
            Mode.WORK -> work
            Mode.PERSONAL -> personal
        }

    /** The current mode's settings. */
    val profile: ModeProfile get() = get(current)

    /** What a polish started now asks for. */
    val polishOptions: PolishOptions
        get() = PolishOptions(current, profile.outputLanguage, profile.learningSummary)
}
