package local.writingassistant.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import local.writingassistant.app.R
import local.writingassistant.core.Provider

/**
 * The provider choice, then the selected provider's API key with Save, Test and Clear, a line
 * on why the key is needed and a link to where it's created.
 *
 * @param below More settings shown after the key, in the same scrolling column.
 */
@Composable
fun SettingsScreen(
    state: SettingsState,
    viewModel: SettingsViewModel,
    modifier: Modifier = Modifier,
    below: @Composable ColumnScope.() -> Unit = {},
) {
    var revealed by rememberSaveable { mutableStateOf(false) }
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ProviderPicker(state.provider, enabled = !state.isTesting, viewModel::selectProvider)
        Text(
            stringResource(whyText(state.provider)),
            style = MaterialTheme.typography.bodyMedium,
        )
        KeyLink(state.provider)
        OutlinedTextField(
            value = state.key,
            onValueChange = viewModel::onKeyChange,
            label = {
                Text(stringResource(R.string.settings_api_key, state.provider.displayName))
            },
            singleLine = true,
            visualTransformation =
                if (revealed) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            trailingIcon = {
                RevealToggle(revealed) { revealed = !revealed }
            },
            modifier = Modifier.fillMaxWidth(),
        )
        val canSubmit = state.key.isNotBlank() && !state.isTesting
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = viewModel::save, enabled = canSubmit) {
                Text(stringResource(R.string.settings_save))
            }
            OutlinedButton(
                onClick = viewModel::test,
                enabled = canSubmit,
                border = outlinedButtonBorder(canSubmit),
            ) {
                Text(stringResource(R.string.settings_test))
            }
            TextButton(
                onClick = viewModel::clear,
                enabled = state.hasStoredKey && !state.isTesting,
            ) {
                Text(stringResource(R.string.settings_clear))
            }
        }
        StatusLine(state.status)
        below()
    }
}

@Composable
private fun ProviderPicker(
    selected: Provider,
    enabled: Boolean,
    onSelect: (Provider) -> Unit,
) {
    Text(stringResource(R.string.settings_provider), style = MaterialTheme.typography.labelLarge)
    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
        Provider.entries.forEachIndexed { index, provider ->
            SegmentedButton(
                selected = provider == selected,
                onClick = { onSelect(provider) },
                shape = SegmentedButtonDefaults.itemShape(index, Provider.entries.size),
                enabled = enabled,
            ) {
                Text(provider.displayName)
            }
        }
    }
}

private fun whyText(provider: Provider): Int =
    when (provider) {
        Provider.ANTHROPIC -> R.string.settings_why_anthropic
        Provider.GROQ -> R.string.settings_why_groq
    }

@Composable
private fun KeyLink(provider: Provider) {
    val label = stringResource(R.string.settings_get_key, provider.displayName)
    val style =
        TextLinkStyles(
            SpanStyle(
                color = MaterialTheme.colorScheme.primary,
                textDecoration = TextDecoration.Underline,
            ),
        )
    val text =
        buildAnnotatedString {
            withLink(LinkAnnotation.Url(provider.keyUrl, style)) { append(label) }
        }
    Text(text, style = MaterialTheme.typography.bodyMedium)
}

@Composable
private fun RevealToggle(
    revealed: Boolean,
    onToggle: () -> Unit,
) {
    TextButton(onClick = onToggle) {
        Text(
            stringResource(
                if (revealed) R.string.settings_hide_key else R.string.settings_show_key,
            ),
        )
    }
}

@Composable
private fun StatusLine(status: SettingsState.Status) {
    val text =
        when (status) {
            SettingsState.Status.Idle -> return
            SettingsState.Status.Saved -> stringResource(R.string.settings_saved)
            SettingsState.Status.Cleared -> stringResource(R.string.settings_cleared)
            SettingsState.Status.Testing -> stringResource(R.string.settings_testing)
            SettingsState.Status.TestPassed -> stringResource(R.string.settings_test_passed)
            is SettingsState.Status.Failed -> status.message
        }
    val color =
        when (status) {
            is SettingsState.Status.Failed -> MaterialTheme.colorScheme.error
            SettingsState.Status.TestPassed -> MaterialTheme.colorScheme.tertiary
            else -> MaterialTheme.colorScheme.onSurfaceVariant
        }
    Text(text, color = color, style = MaterialTheme.typography.bodyMedium)
}
