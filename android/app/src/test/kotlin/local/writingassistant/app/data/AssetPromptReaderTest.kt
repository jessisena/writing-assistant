package local.writingassistant.app.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import local.writingassistant.core.Channel
import local.writingassistant.core.PromptAssembler
import local.writingassistant.core.PromptFile
import local.writingassistant.core.Refinement
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [36])
class AssetPromptReaderTest {
    private val reader =
        AssetPromptReader(ApplicationProvider.getApplicationContext<Context>().assets)

    @Test
    fun everyBundledPromptIsPackagedAsAnAsset() {
        val files =
            listOf(PromptFile.Global) +
                Channel.entries.map { PromptFile.ForChannel(it) } +
                Refinement.entries.map { PromptFile.ForRefinement(it) }

        files.forEach { assertTrue(it.relativePath, reader.read(it).isNotBlank()) }
    }

    @Test
    fun assembledPromptHasNoPlaceholderLeft() {
        val prompt = PromptAssembler(reader).assemble(Channel.FORMAL)

        assertFalse(prompt.contains(PromptFile.CHANNEL_PLACEHOLDER))
    }
}
