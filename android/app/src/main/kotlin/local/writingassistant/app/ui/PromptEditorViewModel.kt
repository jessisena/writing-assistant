package local.writingassistant.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import local.writingassistant.app.AppGraph
import local.writingassistant.core.PromptFile
import local.writingassistant.core.PromptOverrideStore
import local.writingassistant.core.PromptValidationException
import java.io.IOException

/** What the prompt editor renders. */
data class PromptEditorState(
    val text: String = "",
    /** False until the prompt has been read; the field and buttons wait for it. */
    val isLoaded: Boolean = false,
    /** Whether a stored edit is in effect, so Restore default has something to delete. */
    val isCustomized: Boolean = false,
    val status: Status = Status.Idle,
) {
    sealed interface Status {
        data object Idle : Status

        /** Reading, saving or restoring is running. */
        data object Busy : Status

        data object Saved : Status

        data object Restored : Status

        /** [message] is the exception's, shown as is; null when it had none. */
        data class Failed(
            val message: String?,
        ) : Status
    }
}

/**
 * Edits one prompt [file] through [store]: loads the text in effect, saves edits and restores the
 * bundled default. File work runs on [io].
 */
class PromptEditorViewModel(
    private val file: PromptFile,
    private val store: PromptOverrideStore,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {
    private val mutableState = MutableStateFlow(PromptEditorState())
    val state: StateFlow<PromptEditorState> = mutableState.asStateFlow()

    init {
        run {
            val text = store.read(file)
            val customized = store.isCustomized(file)
            mutableState.update {
                it.copy(text = text, isLoaded = true, isCustomized = customized)
            }
        }
    }

    fun onTextChange(text: String) {
        mutableState.update { it.copy(text = text, status = PromptEditorState.Status.Idle) }
    }

    /** Stores the text as the edit; a validation failure is shown and nothing is stored. */
    fun save() {
        val text = state.value.text
        run(PromptEditorState.Status.Saved) {
            store.save(file, text)
            mutableState.update { it.copy(isCustomized = store.isCustomized(file)) }
        }
    }

    /** Deletes the edit and shows the bundled text. */
    fun restoreDefault() {
        run(PromptEditorState.Status.Restored) {
            store.reset(file)
            val text = store.readDefault(file)
            mutableState.update { it.copy(text = text, isCustomized = false) }
        }
    }

    /**
     * Runs [body] on [io] with the status Busy, then sets [done], or Failed with the message of a
     * [PromptValidationException] or [IOException]. Ignored while other work runs.
     */
    private fun run(
        done: PromptEditorState.Status = PromptEditorState.Status.Idle,
        body: () -> Unit,
    ) {
        if (state.value.status == PromptEditorState.Status.Busy) return
        mutableState.update { it.copy(status = PromptEditorState.Status.Busy) }
        viewModelScope.launch {
            val status =
                try {
                    withContext(io) { body() }
                    done
                } catch (e: PromptValidationException) {
                    PromptEditorState.Status.Failed(e.message)
                } catch (e: IOException) {
                    PromptEditorState.Status.Failed(e.message)
                }
            mutableState.update { it.copy(status = status) }
        }
    }

    companion object {
        /** Builds the view model for [file] from the app's singletons. */
        fun factory(
            graph: AppGraph,
            file: PromptFile,
        ): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { PromptEditorViewModel(file, graph.promptStore) }
            }
    }
}
