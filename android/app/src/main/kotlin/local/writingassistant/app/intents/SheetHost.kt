package local.writingassistant.app.intents

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import local.writingassistant.app.AppGraph
import local.writingassistant.app.R
import local.writingassistant.app.WritingAssistantApp
import local.writingassistant.app.ui.Composer
import local.writingassistant.app.ui.ComposerEvent
import local.writingassistant.app.ui.ComposerViewModel
import local.writingassistant.app.ui.Markdown
import local.writingassistant.app.ui.SavedPaletteTheme
import local.writingassistant.app.ui.SettingsScreen
import local.writingassistant.app.ui.SettingsState
import local.writingassistant.app.ui.SettingsViewModel
import local.writingassistant.app.ui.copyPolishedText

/**
 * Shows the composer in a bottom sheet over the calling app, prefilled with [text] when the
 * activity is first created, or when it is restored after process death with an empty session.
 * Blank [text] leaves the session as it is, so an empty share can't wipe a draft or cancel a
 * request. Copy and dismissing the sheet finish the activity. When no API key is stored, the
 * sheet shows Settings first.
 *
 * @param savedInstanceState The activity's; non-null means [text] may already be loaded.
 * @param text The text handed over by the calling app; blank when it sent none.
 * @param onReplace Receives the polished plain text and is expected to finish the activity;
 *   null hides Replace.
 */
fun ComponentActivity.showComposerSheet(
    savedInstanceState: Bundle?,
    text: String,
    onReplace: ((String) -> Unit)?,
) {
    enableEdgeToEdge()
    val graph = (application as WritingAssistantApp).graph
    val composer =
        ViewModelProvider(
            this,
            ComposerViewModel.factory(graph),
        )[ComposerViewModel::class]
    val firstLaunch = savedInstanceState == null
    val sessionInput = composer.state.value.input
    val sessionIsEmpty = sessionInput.isEmpty()
    if (text.isNotBlank() && (firstLaunch || sessionIsEmpty)) {
        composer.onEvent(ComposerEvent.Open(text))
    }
    setContent {
        SavedPaletteTheme(graph.settings.palette) {
            ComposerSheet(graph, composer, onReplace, onFinish = ::finish)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ComposerSheet(
    graph: AppGraph,
    composer: ComposerViewModel,
    onReplace: ((String) -> Unit)?,
    onFinish: () -> Unit,
) {
    val state by composer.state.collectAsStateWithLifecycle()
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var askedForKey by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.needsApiKey) {
        if (state.needsApiKey && !askedForKey) {
            askedForKey = true
            showSettings = true
        }
    }
    val closeSettings = {
        showSettings = false
        composer.onEvent(ComposerEvent.RefreshApiKey)
    }
    ModalBottomSheet(
        onDismissRequest = onFinish,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        val content = Modifier.fillMaxWidth().imePadding()
        if (showSettings) {
            BackHandler(onBack = closeSettings)
            SheetSettings(graph, closeSettings, content)
        } else {
            val context = LocalContext.current
            Composer(
                state = state,
                onEvent = composer::onEvent,
                onCopy = {
                    copyPolishedText(context, state.output)
                    onFinish()
                },
                onReplace =
                    onReplace?.let { replace ->
                        { replace(Markdown.toClipboardText(state.output)) }
                    },
                modifier = content,
            )
        }
    }
}

@Composable
private fun SheetSettings(
    graph: AppGraph,
    onDone: () -> Unit,
    modifier: Modifier,
) {
    val settings: SettingsViewModel = viewModel(factory = SettingsViewModel.factory(graph))
    val settingsState by settings.state.collectAsStateWithLifecycle()
    LaunchedEffect(settingsState.status) {
        val status = settingsState.status
        if (status == SettingsState.Status.Saved || status == SettingsState.Status.TestPassed) {
            onDone()
        }
    }
    Column(modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        ) {
            Text(
                stringResource(R.string.sheet_settings_title),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.sheet_back)) }
        }
        SettingsScreen(settingsState, settings)
    }
}
