package local.writingassistant.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import local.writingassistant.app.AppGraph
import local.writingassistant.app.R
import local.writingassistant.app.data.HistoryRepository
import local.writingassistant.core.HistoryEntry
import java.text.DateFormat
import java.util.Date

/** Deletes history entries and keeps the message of the last file failure for the screen. */
class HistoryViewModel(
    private val history: HistoryRepository,
) : ViewModel() {
    /** Newest first. */
    val entries: StateFlow<List<HistoryEntry>> = history.entries

    private val mutableFailure = MutableStateFlow<String?>(null)

    /** Why the history file couldn't be written; the list on screen has the change anyway. */
    val failure: StateFlow<String?> = mutableFailure.asStateFlow()

    fun delete(id: String) = change { history.delete(id) }

    fun clear() = change { history.clear() }

    private fun change(body: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                body()
                mutableFailure.value = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                mutableFailure.value = e.message ?: e.javaClass.simpleName
            }
        }
    }

    companion object {
        /** Builds the view model from the app's singletons, for `viewModel(factory = …)`. */
        fun factory(graph: AppGraph): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { HistoryViewModel(graph.history) }
            }
    }
}

/**
 * The history, newest first: each row shows the date, the channel and the first line of the
 * output, and has Delete. "Clear all" asks for an inline confirmation.
 *
 * @param entries Newest first.
 * @param failure Shown above the list when the last change couldn't be written.
 * @param actions What tapping a row, Delete and Clear all do.
 */
@Composable
fun HistoryScreen(
    entries: List<HistoryEntry>,
    failure: String?,
    actions: HistoryActions,
    modifier: Modifier = Modifier,
) {
    if (entries.isEmpty() && failure == null) {
        Text(
            stringResource(R.string.history_empty),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = modifier.padding(16.dp),
        )
        return
    }
    val format = remember { DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT) }
    LazyColumn(modifier) {
        item {
            failure?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(16.dp),
                )
            }
            if (entries.isNotEmpty()) ClearAll(actions.onClear)
        }
        items(entries, key = { it.id }) { entry ->
            HistoryRow(entry, format, actions)
            HorizontalDivider()
        }
    }
}

/** The callbacks of [HistoryScreen]. */
class HistoryActions(
    /** Receives the tapped entry's id. */
    val onRestore: (String) -> Unit,
    val onDelete: (String) -> Unit,
    val onClear: () -> Unit,
)

@Composable
private fun ClearAll(onClear: () -> Unit) {
    var confirming by rememberSaveable { mutableStateOf(false) }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.End,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
    ) {
        if (!confirming) {
            TextButton(onClick = { confirming = true }) {
                Text(stringResource(R.string.history_clear_all))
            }
            return@Row
        }
        Text(
            stringResource(R.string.history_clear_confirm),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f).padding(start = 8.dp),
        )
        TextButton(onClick = { confirming = false }) {
            Text(stringResource(R.string.history_clear_cancel))
        }
        TextButton(
            onClick = {
                confirming = false
                onClear()
            },
        ) {
            Text(
                stringResource(R.string.history_clear_yes),
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

@Composable
private fun HistoryRow(
    entry: HistoryEntry,
    format: DateFormat,
    actions: HistoryActions,
) {
    val date = remember(entry.epochSeconds) { format.format(Date(entry.epochSeconds * MILLIS)) }
    val preview = remember(entry.output) { firstLine(entry.output) }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier =
            Modifier
                .fillMaxWidth()
                .clickable { actions.onRestore(entry.id) }
                .padding(start = 16.dp, top = 8.dp, bottom = 8.dp, end = 8.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                stringResource(R.string.history_entry_meta, date, entry.channel.shortName),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(preview, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        TextButton(onClick = { actions.onDelete(entry.id) }) {
            Text(stringResource(R.string.history_delete))
        }
    }
}

/** The first non-blank line of [markdown] as plain text, without Markdown markers. */
internal fun firstLine(markdown: String): String =
    Markdown
        .toClipboardText(markdown)
        .lineSequence()
        .map { it.trim().trimStart('•').trim() }
        .firstOrNull(String::isNotEmpty)
        .orEmpty()

private const val MILLIS = 1_000L
