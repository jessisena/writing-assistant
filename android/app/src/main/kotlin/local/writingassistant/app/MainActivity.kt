package local.writingassistant.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import local.writingassistant.app.ui.Composer
import local.writingassistant.app.ui.ComposerEvent
import local.writingassistant.app.ui.ComposerViewModel
import local.writingassistant.app.ui.SavedPaletteTheme
import local.writingassistant.app.ui.SettingsScreen
import local.writingassistant.app.ui.SettingsViewModel
import local.writingassistant.app.ui.copyPolishedText

/** Full-screen composer with Settings. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val graph = (application as WritingAssistantApp).graph
        setContent {
            SavedPaletteTheme(graph.settings.palette) { MainScreen(graph) }
        }
    }
}

private enum class Screen { Composer, Settings }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MainScreen(graph: AppGraph) {
    val composer: ComposerViewModel = viewModel(factory = ComposerViewModel.factory(graph))
    val state by composer.state.collectAsStateWithLifecycle()
    var screen by rememberSaveable { mutableStateOf(Screen.Composer) }
    var askedForKey by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.needsApiKey) {
        if (state.needsApiKey && !askedForKey) {
            askedForKey = true
            screen = Screen.Settings
        }
    }
    val closeSettings = {
        screen = Screen.Composer
        composer.onEvent(ComposerEvent.RefreshApiKey)
    }
    BackHandler(enabled = screen == Screen.Settings, onBack = closeSettings)
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    val inSettings = screen == Screen.Settings
                    val title = if (inSettings) R.string.settings_title else R.string.app_name
                    Text(stringResource(title))
                },
                navigationIcon = {
                    if (screen == Screen.Settings) {
                        TextButton(
                            onClick = closeSettings,
                        ) { Text(stringResource(R.string.main_back)) }
                    }
                },
                actions = {
                    if (screen == Screen.Composer) {
                        TextButton(onClick = { screen = Screen.Settings }) {
                            Text(stringResource(R.string.main_settings))
                        }
                    }
                },
            )
        },
    ) { padding ->
        val content = Modifier.fillMaxSize().padding(padding).imePadding()
        when (screen) {
            Screen.Composer -> {
                val context = LocalContext.current
                Composer(
                    state = state,
                    onEvent = composer::onEvent,
                    onCopy = { copyPolishedText(context, state.output) },
                    onReplace = null,
                    modifier = content,
                )
            }

            Screen.Settings -> {
                val settings: SettingsViewModel =
                    viewModel(factory = SettingsViewModel.factory(graph))
                val settingsState by settings.state.collectAsStateWithLifecycle()
                SettingsScreen(settingsState, settings, content)
            }
        }
    }
}
