package local.writingassistant.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import local.writingassistant.app.R

/** API key entry with Save, Test and Clear, plus a line on why the key is needed. */
@Composable
fun SettingsScreen(
    state: SettingsState,
    viewModel: SettingsViewModel,
    modifier: Modifier = Modifier,
) {
    var revealed by rememberSaveable { mutableStateOf(false) }
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(stringResource(R.string.settings_why), style = MaterialTheme.typography.bodyMedium)
        OutlinedTextField(
            value = state.key,
            onValueChange = viewModel::onKeyChange,
            label = { Text(stringResource(R.string.settings_api_key)) },
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
            OutlinedButton(onClick = viewModel::test, enabled = canSubmit) {
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
    }
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
            is SettingsState.Status.TestFailed -> status.message
        }
    val color =
        when (status) {
            is SettingsState.Status.TestFailed -> MaterialTheme.colorScheme.error
            SettingsState.Status.TestPassed -> MaterialTheme.colorScheme.tertiary
            else -> MaterialTheme.colorScheme.onSurfaceVariant
        }
    Text(text, color = color, style = MaterialTheme.typography.bodyMedium)
}
