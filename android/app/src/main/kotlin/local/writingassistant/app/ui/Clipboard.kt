package local.writingassistant.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import local.writingassistant.app.R

/**
 * Copies polished [markdown] to the clipboard as HTML, so pasting into rich-text apps keeps
 * the formatting, with a plain-text fallback for apps that don't read HTML.
 */
fun copyPolishedText(
    context: Context,
    markdown: String,
) {
    val clip =
        ClipData.newHtmlText(
            context.getString(R.string.clipboard_label),
            Markdown.toClipboardText(markdown),
            Markdown.toHtml(markdown),
        )
    context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
}
