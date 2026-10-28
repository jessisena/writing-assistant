package local.writingassistant.app.intents

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity

/**
 * "Polish" in the text-selection menu: hosts the composer in a bottom sheet. Replace hands the
 * polished plain text back to the calling app, unless it marked the selection read-only.
 */
class ProcessTextActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString().orEmpty()
        val readOnly = intent.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, false)
        showComposerSheet(savedInstanceState, text, onReplace = ::replace.takeUnless { readOnly })
    }

    private fun replace(polished: String) {
        setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, polished))
        finish()
    }
}
