package local.writingassistant.app.data

import android.content.res.AssetManager
import local.writingassistant.core.PromptFile
import local.writingassistant.core.PromptReading

/** Reads the prompt files bundled as assets from the shared Swift `Prompts` directory. */
class AssetPromptReader(
    private val assets: AssetManager,
) : PromptReading {
    override fun read(file: PromptFile): String =
        assets.open(file.relativePath).bufferedReader().use { it.readText() }
}
