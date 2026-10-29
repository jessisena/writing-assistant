package local.writingassistant.app.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import local.writingassistant.app.R
import local.writingassistant.core.Channel
import local.writingassistant.core.LearningSummary
import local.writingassistant.core.PolishError
import local.writingassistant.core.Refinement

/**
 * The composer shared by the full-screen app and the bottom sheet: channel chips, input,
 * Polish with progress and Cancel, then the editable result, the learning summary,
 * refinements, Copy and (when the host supports it) Replace. Copy and Replace send
 * [ComposerEvent.SaveOutput] before calling the host, so the history keeps the text as shown.
 *
 * @param state What to render, from [ComposerViewModel.state].
 * @param onEvent Receives every user action; pass [ComposerViewModel.onEvent].
 * @param onCopy Called when Copy is tapped; the host copies `state.output` (see
 *   [copyPolishedText]) and may close itself.
 * @param onReplace Called when Replace is tapped; null hides the button.
 */
@Composable
fun Composer(
    state: ComposerState,
    onEvent: (ComposerEvent) -> Unit,
    onCopy: () -> Unit,
    onReplace: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ChannelChips(state.enabledChannels, state.channel) {
            onEvent(ComposerEvent.ChannelSelected(it))
        }
        OutlinedTextField(
            value = state.input,
            onValueChange = { onEvent(ComposerEvent.InputChanged(it)) },
            label = { Text(stringResource(R.string.composer_input_label)) },
            minLines = 4,
            modifier = Modifier.fillMaxWidth(),
        )
        state.error?.let { ErrorBanner(it, onEvent) }
        if (state.needsApiKey) {
            Text(
                stringResource(R.string.composer_needs_key),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
        }
        PolishRow(state, onEvent)
        if (state.result != null || state.output.isNotEmpty()) {
            ResultSection(state, onEvent, onCopy, onReplace)
        }
    }
}

@Composable
private fun ChannelChips(
    channels: List<Channel>,
    selected: Channel,
    onSelect: (Channel) -> Unit,
) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        for (channel in channels) {
            val isSelected = channel == selected
            FilterChip(
                selected = isSelected,
                onClick = { onSelect(channel) },
                label = { Text(channel.shortName) },
                leadingIcon = if (isSelected) ({ Text("✓") }) else null,
                border =
                    FilterChipDefaults.filterChipBorder(
                        enabled = true,
                        selected = isSelected,
                        borderColor = MaterialTheme.colorScheme.outline,
                    ),
            )
        }
    }
}

@Composable
private fun ErrorBanner(
    error: PolishError,
    onEvent: (ComposerEvent) -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(error.message, style = MaterialTheme.typography.bodyMedium)
            Row(Modifier.align(Alignment.End)) {
                TextButton(onClick = { onEvent(ComposerEvent.DismissError) }) {
                    Text(stringResource(R.string.composer_dismiss))
                }
                TextButton(onClick = { onEvent(ComposerEvent.Retry) }) {
                    Text(stringResource(R.string.composer_retry))
                }
            }
        }
    }
}

@Composable
private fun PolishRow(
    state: ComposerState,
    onEvent: (ComposerEvent) -> Unit,
) {
    val phase = state.phase
    if (phase !is ComposerState.Phase.Working) {
        Button(
            onClick = { onEvent(ComposerEvent.Polish) },
            enabled = state.canPolish,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(stringResource(R.string.composer_polish))
        }
        return
    }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
        Spacer(Modifier.width(12.dp))
        val isRefining = phase.refinement != null
        val label = if (isRefining) R.string.composer_refining else R.string.composer_polishing
        Text(stringResource(label), Modifier.weight(1f))
        TextButton(onClick = { onEvent(ComposerEvent.Cancel) }) {
            Text(stringResource(R.string.composer_cancel))
        }
    }
}

@Composable
private fun ResultSection(
    state: ComposerState,
    onEvent: (ComposerEvent) -> Unit,
    onCopy: () -> Unit,
    onReplace: (() -> Unit)?,
) {
    OutputArea(
        state.output,
        enabled = !state.isWorking,
    ) { onEvent(ComposerEvent.OutputChanged(it)) }
    if (state.showLearningSummary) {
        state.result
            ?.learningSummary
            ?.takeUnless { it.isEmpty }
            ?.let { LearningSummarySection(it) }
    }
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (refinement in Refinement.entries) {
            OutlinedButton(
                onClick = { onEvent(ComposerEvent.Refine(refinement)) },
                enabled = state.canUseOutput,
                border = outlinedButtonBorder(state.canUseOutput),
            ) {
                Text(refinement.displayName)
            }
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        Button(
            onClick = {
                onEvent(ComposerEvent.SaveOutput)
                onCopy()
            },
            enabled = state.canUseOutput,
            modifier = Modifier.weight(1f),
        ) {
            Text(stringResource(R.string.composer_copy))
        }
        if (onReplace != null) {
            Button(
                onClick = {
                    onEvent(ComposerEvent.SaveOutput)
                    onReplace()
                },
                enabled = state.canUseOutput,
                modifier = Modifier.weight(1f),
            ) {
                Text(stringResource(R.string.composer_replace))
            }
        }
    }
}

@Composable
private fun OutputArea(
    output: String,
    enabled: Boolean,
    onChange: (String) -> Unit,
) {
    var editing by rememberSaveable { mutableStateOf(false) }
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.composer_result_label),
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = { editing = !editing }, enabled = enabled) {
                Text(
                    stringResource(
                        if (editing) R.string.composer_done_editing else R.string.composer_edit,
                    ),
                )
            }
        }
        if (editing && enabled) {
            OutlinedTextField(
                value = output,
                onValueChange = onChange,
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            Surface(
                shape = MaterialTheme.shapes.small,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                modifier = Modifier.fillMaxWidth(),
            ) {
                val linkColor = MaterialTheme.colorScheme.primary
                val text =
                    remember(output, linkColor) { Markdown.toAnnotatedString(output, linkColor) }
                Text(text, Modifier.padding(16.dp))
            }
        }
    }
}

@Composable
private fun LearningSummarySection(summary: LearningSummary) {
    var expanded by rememberSaveable(summary) { mutableStateOf(false) }
    val tips =
        summary.corrections.size + summary.vocabulary.size +
            if (summary.grammarInsight.isEmpty()) 0 else 1
    Column(Modifier.fillMaxWidth()) {
        Text(
            (if (expanded) "▾ " else "▸ ") +
                pluralStringResource(R.plurals.composer_what_changed, tips, tips),
            style = MaterialTheme.typography.titleSmall,
            modifier =
                Modifier.fillMaxWidth().clickable { expanded = !expanded }.padding(
                    vertical = 8.dp,
                ),
        )
        if (expanded) LearningSummaryDetails(summary)
    }
}

@Composable
private fun LearningSummaryDetails(summary: LearningSummary) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (summary.corrections.isNotEmpty()) {
            SummaryHeading(R.string.composer_corrections)
            for (correction in summary.corrections) {
                Text(
                    stringResource(
                        R.string.composer_correction,
                        correction.original,
                        correction.corrected,
                    ),
                )
                Text(correction.why, style = MaterialTheme.typography.bodySmall)
            }
        }
        if (summary.grammarInsight.isNotEmpty()) {
            SummaryHeading(R.string.composer_grammar)
            Text(summary.grammarInsight)
        }
        if (summary.vocabulary.isNotEmpty()) {
            SummaryHeading(R.string.composer_vocabulary)
            for (item in summary.vocabulary) {
                Text(stringResource(R.string.composer_vocabulary_item, item.term, item.meaning))
                Text(item.example, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun SummaryHeading(
    @StringRes text: Int,
) {
    Text(
        stringResource(text),
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
    )
}
