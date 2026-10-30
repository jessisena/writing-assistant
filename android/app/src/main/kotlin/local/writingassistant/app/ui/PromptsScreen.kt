package local.writingassistant.app.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import local.writingassistant.app.R
import local.writingassistant.core.PromptFile
import local.writingassistant.core.PromptOverrideStore

/**
 * The prompt files [store] has an edit for, read off the main thread each time the caller enters
 * the composition; null until read.
 */
@Composable
fun rememberCustomizedPrompts(store: PromptOverrideStore): Set<PromptFile>? {
    val customized by produceState<Set<PromptFile>?>(null, store) {
        value = withContext(Dispatchers.IO) { PromptFile.all.filter(store::isCustomized).toSet() }
    }
    return customized
}

/**
 * Every prompt file, grouped as global rules, channels and refinements, each marked "Edited" when
 * [customized] holds it.
 *
 * @param customized Null while still being read; no file is marked meanwhile.
 * @param onOpen Called with the tapped file.
 */
@Composable
fun PromptListScreen(
    customized: Set<PromptFile>?,
    onOpen: (PromptFile) -> Unit,
    modifier: Modifier = Modifier,
) {
    val edited = customized.orEmpty()
    Column(modifier.verticalScroll(rememberScrollState()).padding(vertical = 8.dp)) {
        PromptGroup(
            R.string.prompts_group_global,
            listOf(
                PromptFile.Global,
                PromptFile.Always,
                PromptFile.LearningSummary,
                PromptFile.Refine,
            ),
            edited,
            onOpen,
        )
        PromptGroup(
            R.string.prompts_group_modes,
            PromptFile.all.filter { it is PromptFile.ForMode || it is PromptFile.ForLanguage },
            edited,
            onOpen,
        )
        PromptGroup(
            R.string.prompts_group_channels,
            PromptFile.all.filterIsInstance<PromptFile.ForChannel>(),
            edited,
            onOpen,
        )
        PromptGroup(
            R.string.prompts_group_refinements,
            PromptFile.all.filterIsInstance<PromptFile.ForRefinement>(),
            edited,
            onOpen,
        )
    }
}

@Composable
private fun PromptGroup(
    @StringRes title: Int,
    files: List<PromptFile>,
    edited: Set<PromptFile>,
    onOpen: (PromptFile) -> Unit,
) {
    Text(
        stringResource(title),
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
    )
    for (file in files) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier =
                Modifier
                    .fillMaxWidth()
                    .clickable { onOpen(file) }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
        ) {
            Text(file.displayName, Modifier.weight(1f))
            if (file in edited) {
                Text(
                    stringResource(R.string.prompts_edited),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }
        }
    }
}

/**
 * Edits one prompt: a monospace field with Save, Restore default (confirmed inline, since it
 * deletes the edit) and a status or error line.
 */
@Composable
fun PromptEditorScreen(
    viewModel: PromptEditorViewModel,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val idle = state.isLoaded && state.status != PromptEditorState.Status.Busy
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.isLoaded) {
            val origin =
                if (state.isCustomized) {
                    R.string.prompt_editor_customized
                } else {
                    R.string.prompt_editor_default
                }
            Text(
                stringResource(origin),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = state.text,
                onValueChange = viewModel::onTextChange,
                label = { Text(stringResource(R.string.prompt_editor_label)) },
                textStyle =
                    MaterialTheme.typography.bodyMedium.copy(
                        fontFamily = FontFamily.Monospace,
                    ),
                enabled = idle,
                minLines = EDITOR_MIN_LINES,
                modifier = Modifier.fillMaxWidth(),
            )
            Button(onClick = viewModel::save, enabled = idle) {
                Text(stringResource(R.string.prompt_editor_save))
            }
            RestoreDefault(
                enabled = idle && state.isCustomized,
                onRestore = viewModel::restoreDefault,
            )
        }
        EditorStatus(state.status)
    }
}

@Composable
private fun RestoreDefault(
    enabled: Boolean,
    onRestore: () -> Unit,
) {
    var confirming by rememberSaveable { mutableStateOf(false) }
    if (!confirming) {
        OutlinedButton(
            onClick = { confirming = true },
            enabled = enabled,
            border = outlinedButtonBorder(enabled),
        ) {
            Text(stringResource(R.string.prompt_editor_restore))
        }
        return
    }
    Text(
        stringResource(R.string.prompt_editor_restore_confirm),
        style = MaterialTheme.typography.bodyMedium,
    )
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(
            onClick = {
                confirming = false
                onRestore()
            },
        ) {
            Text(stringResource(R.string.prompt_editor_restore_yes))
        }
        TextButton(onClick = { confirming = false }) {
            Text(stringResource(R.string.prompt_editor_restore_no))
        }
    }
}

@Composable
private fun EditorStatus(status: PromptEditorState.Status) {
    val text =
        when (status) {
            PromptEditorState.Status.Idle, PromptEditorState.Status.Busy -> {
                return
            }

            PromptEditorState.Status.Saved -> {
                stringResource(R.string.prompt_editor_saved)
            }

            PromptEditorState.Status.Restored -> {
                stringResource(R.string.prompt_editor_restored)
            }

            is PromptEditorState.Status.Failed -> {
                status.message ?: stringResource(R.string.prompt_editor_failed)
            }
        }
    val color =
        if (status is PromptEditorState.Status.Failed) {
            MaterialTheme.colorScheme.error
        } else {
            MaterialTheme.colorScheme.tertiary
        }
    Text(text, color = color, style = MaterialTheme.typography.bodyMedium)
}

private const val EDITOR_MIN_LINES = 12
