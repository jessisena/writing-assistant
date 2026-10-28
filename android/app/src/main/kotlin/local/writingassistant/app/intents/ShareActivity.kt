package local.writingassistant.app.intents

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity

/** Share target for plain text: hosts the composer in a bottom sheet, Copy only. */
class ShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString().orEmpty()
        showComposerSheet(savedInstanceState, text, onReplace = null)
    }
}
