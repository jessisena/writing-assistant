package local.writingassistant.app.data

import android.content.Context
import local.writingassistant.core.Channel

/** [AppSettings] persisted in Preferences DataStore. */
class DataStoreAppSettings(
    private val context: Context,
) : AppSettings {
    override suspend fun lastChannel(): Channel? = TODO("client worker ($context)")

    override suspend fun setLastChannel(channel: Channel): Unit = TODO("client worker")
}
