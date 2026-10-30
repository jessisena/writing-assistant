package local.writingassistant.app.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import local.writingassistant.app.R
import local.writingassistant.app.data.PalettePreset
import local.writingassistant.core.Channel
import local.writingassistant.core.Mode
import local.writingassistant.core.OutputLanguage

/**
 * The main app's preferences: per mode (picked with a Work/Personal control) the output
 * language, the English learning summary switch and a switch per channel ("Writing for"); then
 * the palette choice and a row that opens the prompt list. Shows nothing until the preferences
 * have loaded.
 *
 * @param onOpenPrompts Called when the Prompts row is tapped.
 */
@Composable
fun PreferencesSection(
    viewModel: PreferencesViewModel,
    onOpenPrompts: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val failure by viewModel.failure.collectAsStateWithLifecycle()
    val current = state ?: return
    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HorizontalDivider()
        ModeSettingsSection(current, viewModel)
        HorizontalDivider()
        PalettePicker(current.palette, viewModel::setPalette)
        HorizontalDivider()
        PromptsRow(onOpenPrompts)
        failure?.let {
            Text(
                stringResource(R.string.prefs_failed, it),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun ModeSettingsSection(
    state: PreferencesState,
    viewModel: PreferencesViewModel,
) {
    Heading(R.string.prefs_modes)
    Hint(R.string.prefs_modes_hint)
    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
        Mode.entries.forEachIndexed { index, mode ->
            SegmentedButton(
                selected = mode == state.editing,
                onClick = { viewModel.edit(mode) },
                shape = SegmentedButtonDefaults.itemShape(index, Mode.entries.size),
            ) {
                Text(mode.displayName)
            }
        }
    }
    Heading(R.string.prefs_output_language)
    for (language in OutputLanguage.entries) {
        RadioRow(
            label = language.displayName,
            selected = language == state.profile.outputLanguage,
            onSelect = { viewModel.setOutputLanguage(language) },
        )
    }
    SwitchRow(
        label = stringResource(R.string.prefs_summary),
        checked = state.profile.learningSummary,
        onChange = viewModel::setLearningSummary,
    )
    Hint(R.string.prefs_summary_hint)
    ChannelSwitches(state, viewModel::setChannelVisible)
}

@Composable
private fun ChannelSwitches(
    state: PreferencesState,
    onChange: (Channel, Boolean) -> Unit,
) {
    Heading(R.string.prefs_writing_for)
    Hint(R.string.prefs_writing_for_hint)
    for (channel in Channel.entries) {
        SwitchRow(
            label = channel.displayName,
            checked = channel in state.profile.visibleChannels,
            enabled = !state.profile.isOnlyVisible(channel),
            onChange = { onChange(channel, it) },
        )
    }
}

@Composable
private fun RadioRow(
    label: String,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier =
            Modifier
                .fillMaxWidth()
                .selectable(selected = selected, role = Role.RadioButton, onClick = onSelect),
    ) {
        RadioButton(selected = selected, onClick = null)
        Text(label, Modifier.padding(start = 12.dp))
    }
}

@Composable
private fun PalettePicker(
    selected: PalettePreset,
    onSelect: (PalettePreset) -> Unit,
) {
    Heading(R.string.prefs_appearance)
    for (palette in PalettePreset.entries) {
        RadioRow(palette.displayName, palette == selected) { onSelect(palette) }
    }
}

@Composable
private fun PromptsRow(onOpen: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(vertical = 4.dp)) {
        Heading(R.string.prefs_prompts)
        Hint(R.string.prefs_prompts_hint)
    }
}

@Composable
private fun SwitchRow(
    label: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    enabled: Boolean = true,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier =
            Modifier
                .fillMaxWidth()
                .toggleable(
                    value = checked,
                    enabled = enabled,
                    role = Role.Switch,
                    onValueChange = onChange,
                ),
    ) {
        Text(label, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

@Composable
private fun Heading(
    @StringRes text: Int,
) {
    Text(stringResource(text), style = MaterialTheme.typography.labelLarge)
}

@Composable
private fun Hint(
    @StringRes text: Int,
) {
    Text(
        stringResource(text),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
