package local.writingassistant.app.data

import local.writingassistant.core.Channel

/** Small user preferences that aren't secret. */
interface AppSettings {
    /** The channel used last, preselected in the composer. Null on first run. */
    suspend fun lastChannel(): Channel?

    suspend fun setLastChannel(channel: Channel)
}
