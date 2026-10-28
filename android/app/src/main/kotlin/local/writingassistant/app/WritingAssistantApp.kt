package local.writingassistant.app

import android.app.Application

class WritingAssistantApp : Application() {
    val graph: AppGraph by lazy { DefaultAppGraph(this) }
}
