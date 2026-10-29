package local.writingassistant.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.annotation.StringRes
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
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import local.writingassistant.app.ui.HistoryActions
import local.writingassistant.app.ui.HistoryScreen
import local.writingassistant.app.ui.HistoryViewModel
import local.writingassistant.app.ui.PreferencesSection
import local.writingassistant.app.ui.PreferencesViewModel
import local.writingassistant.app.ui.PromptEditorScreen
import local.writingassistant.app.ui.PromptEditorViewModel
import local.writingassistant.app.ui.PromptListScreen
import local.writingassistant.app.ui.SavedPaletteTheme
import local.writingassistant.app.ui.SettingsScreen
import local.writingassistant.app.ui.SettingsViewModel
import local.writingassistant.app.ui.copyPolishedText
import local.writingassistant.app.ui.rememberCustomizedPrompts
import local.writingassistant.core.PromptFile

/** Full-screen composer with History, Settings and the prompt editor. */
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

/** The app's screens; Back goes to [parent]. Parents are declared before their children. */
private enum class Screen(
    @StringRes val title: Int,
    val parent: Screen?,
) {
    Composer(R.string.app_name, null),
    Settings(R.string.settings_title, Composer),
    History(R.string.history_title, Composer),
    Prompts(R.string.prompts_title, Settings),
    PromptEditor(R.string.prompts_title, Prompts),
}

/**
 * Where the main screen is: the screen, and on [Screen.PromptEditor] the edited prompt's path.
 * Both survive recreation; [onLeaveSettings] runs whenever Back leaves Settings.
 * [promptOpenedState] is true from [openPrompt] until the editor has reloaded the prompt, so a new
 * visit starts from the stored text while a recreation keeps the unsaved edit.
 */
private class Navigation(
    private val screenState: MutableState<Screen>,
    private val promptPathState: MutableState<String?>,
    private val promptOpenedState: MutableState<Boolean>,
    private val onLeaveSettings: () -> Unit,
) {
    val screen: Screen get() = screenState.value

    /** The prompt being edited; null when the saved path no longer names one. */
    val prompt: PromptFile? get() = promptPathState.value?.let(PromptFile::fromRelativePath)

    fun open(target: Screen) {
        screenState.value = target
    }

    fun openPrompt(file: PromptFile) {
        promptPathState.value = file.relativePath
        promptOpenedState.value = true
        screenState.value = Screen.PromptEditor
    }

    /** Returns true once per [openPrompt]. */
    fun consumePromptOpened(): Boolean {
        val opened = promptOpenedState.value
        promptOpenedState.value = false
        return opened
    }

    fun up() {
        if (screen == Screen.Settings) onLeaveSettings()
        screenState.value = screen.parent ?: return
    }
}

@Composable
private fun rememberNavigation(onLeaveSettings: () -> Unit): Navigation {
    val screen = rememberSaveable { mutableStateOf(Screen.Composer) }
    val promptPath = rememberSaveable { mutableStateOf<String?>(null) }
    val promptOpened = rememberSaveable { mutableStateOf(false) }
    return remember(screen, promptPath, promptOpened) {
        Navigation(screen, promptPath, promptOpened, onLeaveSettings)
    }
}

@Composable
private fun MainScreen(graph: AppGraph) {
    val composer: ComposerViewModel = viewModel(factory = ComposerViewModel.factory(graph))
    val state by composer.state.collectAsStateWithLifecycle()
    val navigation = rememberNavigation { composer.onEvent(ComposerEvent.RefreshApiKey) }
    var askedForKey by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.needsApiKey) {
        if (state.needsApiKey && !askedForKey) {
            askedForKey = true
            navigation.open(Screen.Settings)
        }
    }
    BackHandler(enabled = navigation.screen != Screen.Composer, onBack = navigation::up)
    Scaffold(topBar = { MainTopBar(navigation) }) { padding ->
        val content = Modifier.fillMaxSize().padding(padding).imePadding()
        when (navigation.screen) {
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
                MainSettings(graph, navigation, content)
            }

            Screen.History -> {
                MainHistory(graph, composer, state.isWorking, navigation, content)
            }

            Screen.Prompts -> {
                PromptListScreen(
                    rememberCustomizedPrompts(graph.promptStore),
                    navigation::openPrompt,
                    content,
                )
            }

            Screen.PromptEditor -> {
                MainPromptEditor(graph, navigation, content)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MainTopBar(navigation: Navigation) {
    val screen = navigation.screen
    TopAppBar(
        title = {
            val prompt = navigation.prompt
            if (screen == Screen.PromptEditor && prompt != null) {
                Text(prompt.displayName)
            } else {
                Text(stringResource(screen.title))
            }
        },
        navigationIcon = {
            if (screen != Screen.Composer) {
                TextButton(onClick = navigation::up) { Text(stringResource(R.string.main_back)) }
            }
        },
        actions = {
            if (screen == Screen.Composer) {
                TextButton(onClick = { navigation.open(Screen.History) }) {
                    Text(stringResource(R.string.main_history))
                }
                TextButton(onClick = { navigation.open(Screen.Settings) }) {
                    Text(stringResource(R.string.main_settings))
                }
            }
        },
    )
}

@Composable
private fun MainSettings(
    graph: AppGraph,
    navigation: Navigation,
    modifier: Modifier,
) {
    val settings: SettingsViewModel = viewModel(factory = SettingsViewModel.factory(graph))
    val settingsState by settings.state.collectAsStateWithLifecycle()
    val preferences: PreferencesViewModel =
        viewModel(factory = PreferencesViewModel.factory(graph))
    SettingsScreen(settingsState, settings, modifier) {
        PreferencesSection(preferences, onOpenPrompts = { navigation.open(Screen.Prompts) })
    }
}

@Composable
private fun MainHistory(
    graph: AppGraph,
    composer: ComposerViewModel,
    isWorking: Boolean,
    navigation: Navigation,
    modifier: Modifier,
) {
    val history: HistoryViewModel = viewModel(factory = HistoryViewModel.factory(graph))
    val entries by history.entries.collectAsStateWithLifecycle()
    val failure by history.failure.collectAsStateWithLifecycle()
    val actions =
        HistoryActions(
            onRestore = { id ->
                composer.onEvent(ComposerEvent.RestoreHistory(id))
                navigation.up()
            },
            onDelete = history::delete,
            onClear = history::clear,
            canRestore = !isWorking,
        )
    HistoryScreen(entries, failure, actions, modifier)
}

@Composable
private fun MainPromptEditor(
    graph: AppGraph,
    navigation: Navigation,
    modifier: Modifier,
) {
    val file = navigation.prompt
    if (file == null) {
        LaunchedEffect(Unit) { navigation.up() }
        return
    }
    val editor: PromptEditorViewModel =
        viewModel(key = file.relativePath, factory = PromptEditorViewModel.factory(graph, file))
    LaunchedEffect(editor) {
        if (navigation.consumePromptOpened()) editor.reload()
    }
    PromptEditorScreen(editor, modifier)
}
