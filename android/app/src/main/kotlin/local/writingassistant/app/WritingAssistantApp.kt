package local.writingassistant.app

import android.app.Application

/** Holds the [AppGraph]; tests subclass it to swap in fakes. */
open class WritingAssistantApp : Application() {
    open val graph: AppGraph by lazy { DefaultAppGraph(this) }
}
