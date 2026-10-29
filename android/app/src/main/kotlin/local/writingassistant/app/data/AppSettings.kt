package local.writingassistant.app.data

import local.writingassistant.core.Channel
import local.writingassistant.core.Provider

/** Small user preferences that aren't secret. */
interface AppSettings {
    /** The channel used last, preselected in the composer. Null on first run. */
    suspend fun lastChannel(): Channel?

    suspend fun setLastChannel(channel: Channel)

    /** The provider that handles requests. [Provider.ANTHROPIC] until the user picks another. */
    suspend fun provider(): Provider

    suspend fun setProvider(provider: Provider)
}
