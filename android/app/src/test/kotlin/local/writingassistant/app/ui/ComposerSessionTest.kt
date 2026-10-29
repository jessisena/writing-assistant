package local.writingassistant.app.ui

import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import local.writingassistant.app.data.AppSettings
import local.writingassistant.app.data.HistoryRepository
import local.writingassistant.app.ui.ComposerEvent.Cancel
import local.writingassistant.app.ui.ComposerEvent.ChannelSelected
import local.writingassistant.app.ui.ComposerEvent.DismissError
import local.writingassistant.app.ui.ComposerEvent.Open
import local.writingassistant.app.ui.ComposerEvent.OutputChanged
import local.writingassistant.app.ui.ComposerEvent.Polish
import local.writingassistant.app.ui.ComposerEvent.Refine
import local.writingassistant.app.ui.ComposerEvent.RestoreHistory
import local.writingassistant.app.ui.ComposerEvent.SaveOutput
import local.writingassistant.app.ui.ComposerState.Phase
import local.writingassistant.core.Channel
import local.writingassistant.core.HistoryEntry
import local.writingassistant.core.HistoryStoreException
import local.writingassistant.core.LearningSummary
import local.writingassistant.core.PolishError
import local.writingassistant.core.PolishResult
import local.writingassistant.core.Provider
import local.writingassistant.core.Refinement
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class ComposerSessionTest {
    private val dispatcher = StandardTestDispatcher()
    private val polisher = FakePolishing()
    private val gate = CompletableDeferred<Unit>()

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        polisher.onPolish = {
            gate.await()
            FakePolishing.result(it)
        }
    }

    @After
    fun tearDown() {
        sessionScope.cancel()
        Dispatchers.resetMain()
    }

    private val sessionScope = CoroutineScope(SupervisorJob() + dispatcher)

    private fun session(
        settings: AppSettings = FakeAppSettings(),
        history: HistoryRepository = testHistory(),
    ) = ComposerSession(polisher, settings, FakeApiKeyStore(), history, sessionScope)

    private val savedEntry =
        HistoryEntry(
            id = "saved",
            epochSeconds = 1,
            channel = Channel.EMAIL,
            input = "old input",
            output = "old output",
            learningSummary = LearningSummary(emptyList(), "insight", emptyList()),
            detectedLanguage = "pt",
            wasTranslated = true,
            modelUsed = "model",
        )

    private fun HistoryRepository.outputs() = entries.value.map { it.output }

    /** Opens [text] and polishes it to the end. */
    private fun TestScope.polished(
        session: ComposerSession,
        text: String,
    ) {
        if (!gate.isCompleted) gate.complete(Unit)
        session.onEvent(Open(text))
        session.onEvent(Polish)
        advanceUntilIdle()
    }

    /** A view model owned by [store], the way an activity owns it. */
    private fun viewModelIn(
        store: ViewModelStore,
        session: ComposerSession,
    ): ComposerViewModel {
        val factory = viewModelFactory { initializer { ComposerViewModel(session) } }
        return ViewModelProvider.create(store, factory)[ComposerViewModel::class]
    }

    private fun TestScope.startPolishInClosedSheet(session: ComposerSession) {
        val sheet = ViewModelStore()
        val vm = viewModelIn(sheet, session)
        vm.onEvent(Open("hey"))
        vm.onEvent(Polish)
        advanceUntilIdle()
        sheet.clear()
    }

    @Test
    fun `a request keeps running after its screen is closed`() =
        runTest(dispatcher) {
            val session = session()
            startPolishInClosedSheet(session)
            gate.complete(Unit)
            advanceUntilIdle()
            val app = viewModelIn(ViewModelStore(), session)
            assertEquals(Phase.Idle, app.state.value.phase)
            assertEquals("polished: hey", app.state.value.output)
        }

    @Test
    fun `cancel from another screen stops a request started in the sheet`() =
        runTest(dispatcher) {
            val session = session()
            startPolishInClosedSheet(session)
            val app = viewModelIn(ViewModelStore(), session)
            assertEquals(Phase.Working(null), app.state.value.phase)
            app.onEvent(Cancel)
            gate.complete(Unit)
            advanceUntilIdle()
            assertEquals(Phase.Idle, app.state.value.phase)
            assertEquals("", app.state.value.output)
        }

    @Test
    fun `opening the same text again keeps the result`() =
        runTest(dispatcher) {
            val session = session()
            gate.complete(Unit)
            session.onEvent(Open("hey"))
            session.onEvent(Polish)
            advanceUntilIdle()
            session.onEvent(Open("hey"))
            assertEquals("polished: hey", session.state.value.output)
        }

    @Test
    fun `opening new text cancels the request and starts over`() =
        runTest(dispatcher) {
            val session = session()
            session.onEvent(ChannelSelected(Channel.FORMAL))
            session.onEvent(Open("hey"))
            session.onEvent(Polish)
            advanceUntilIdle()
            session.onEvent(Open("other"))
            gate.complete(Unit)
            advanceUntilIdle()
            val state = session.state.value
            assertEquals(ComposerState(input = "other", channel = Channel.FORMAL), state)
        }

    @Test
    fun `opening new text clears an error and its retry`() =
        runTest(dispatcher) {
            val session = session()
            polisher.onPolish = { throw PolishError.Overloaded }
            session.onEvent(Open("hey"))
            session.onEvent(Polish)
            advanceUntilIdle()
            session.onEvent(Open("other"))
            assertNull(session.state.value.error)
            session.onEvent(ComposerEvent.Retry)
            advanceUntilIdle()
            assertEquals(1, polisher.calls.size)
        }

    @Test
    fun `a key storage failure while checking the key is shown`() =
        runTest(dispatcher) {
            val failure = PolishError.KeyStorageFailed("ProviderException")
            val session =
                ComposerSession(
                    polisher,
                    FakeAppSettings(),
                    FailingKeyStore(failure),
                    testHistory(),
                    sessionScope,
                )

            session.onEvent(ComposerEvent.RefreshApiKey)
            advanceUntilIdle()

            assertEquals(failure, session.state.value.error)
        }

    @Test
    fun `an unexpected failure ends the request with an error that can be retried`() =
        runTest(dispatcher) {
            val session = session()
            polisher.onPolish = { throw IllegalStateException("boom") }
            session.onEvent(Open("hey"))
            session.onEvent(Polish)
            advanceUntilIdle()

            val state = session.state.value
            assertEquals(PolishError.Unexpected("IllegalStateException"), state.error)
            assertEquals(Phase.Idle, state.phase)
            polisher.onPolish = { FakePolishing.result(it) }
            session.onEvent(ComposerEvent.Retry)
            advanceUntilIdle()
            assertEquals("polished: hey", session.state.value.output)
        }

    @Test
    fun `a settings failure is shown instead of crashing`() =
        runTest(dispatcher) {
            val settings =
                object : AppSettings by FakeAppSettings() {
                    override suspend fun lastChannel(): Channel? = throw IOException("disk")

                    override suspend fun setLastChannel(channel: Channel) =
                        throw IOException("disk")
                }
            val session =
                ComposerSession(polisher, settings, FakeApiKeyStore(), testHistory(), sessionScope)
            advanceUntilIdle()

            assertEquals(PolishError.Unexpected("IOException"), session.state.value.error)
            session.onEvent(DismissError)
            session.onEvent(ChannelSelected(Channel.FORMAL))
            advanceUntilIdle()
            assertEquals(Channel.FORMAL, session.state.value.channel)
            assertEquals(PolishError.Unexpected("IOException"), session.state.value.error)
        }

    @Test
    fun `the key check uses the selected provider`() =
        runTest(dispatcher) {
            val keys = FakeApiKeyStore(key = "sk-ant-fake")
            val settings = FakeAppSettings(provider = Provider.GROQ)
            val session = ComposerSession(polisher, settings, keys, testHistory(), sessionScope)

            session.onEvent(ComposerEvent.RefreshApiKey)
            advanceUntilIdle()
            assertTrue(session.state.value.needsApiKey)

            keys.keys[Provider.GROQ] = "gsk-fake"
            session.onEvent(ComposerEvent.RefreshApiKey)
            advanceUntilIdle()
            assertFalse(session.state.value.needsApiKey)
        }

    @Test
    fun `disabled channels are hidden and a hidden selection moves to the first shown`() =
        runTest(dispatcher) {
            val settings = FakeAppSettings()
            val session = session(settings)
            session.onEvent(ChannelSelected(Channel.FORMAL))
            settings.disabledChannels.value = setOf(Channel.SLACK, Channel.FORMAL)
            advanceUntilIdle()

            val state = session.state.value
            assertEquals(Channel.entries - Channel.SLACK - Channel.FORMAL, state.enabledChannels)
            assertEquals(Channel.SLACK_INFORMAL, state.channel)
            assertEquals(Channel.FORMAL, settings.channel)
        }

    @Test
    fun `turning every channel off still shows them all`() =
        runTest(dispatcher) {
            val settings = FakeAppSettings()
            val session = session(settings)
            settings.disabledChannels.value = Channel.entries.toSet()
            advanceUntilIdle()

            assertEquals(Channel.entries, session.state.value.enabledChannels)
            assertEquals(Channel.SLACK, session.state.value.channel)
        }

    @Test
    fun `a restored last channel that is now hidden falls back`() =
        runTest(dispatcher) {
            val settings = FakeAppSettings(channel = Channel.EMAIL)
            settings.disabledChannels.value = setOf(Channel.SLACK, Channel.EMAIL)
            val session = session(settings)
            advanceUntilIdle()

            assertEquals(Channel.SLACK_INFORMAL, session.state.value.channel)
            assertEquals(Channel.EMAIL, settings.channel)
        }

    @Test
    fun `the learning summary setting is shown and sent with each polish`() =
        runTest(dispatcher) {
            val settings = FakeAppSettings()
            settings.learningSummaryEnabled.value = false
            val session = session(settings)
            advanceUntilIdle()
            assertFalse(session.state.value.showLearningSummary)

            polished(session, "hey")
            settings.learningSummaryEnabled.value = true
            advanceUntilIdle()
            session.onEvent(Polish)
            advanceUntilIdle()

            assertTrue(session.state.value.showLearningSummary)
            assertEquals(listOf(false, true), polisher.learningSummaryRequests)
        }

    @Test
    fun `a successful polish is recorded in the history`() =
        runTest(dispatcher) {
            val history = testHistory()
            val session = session(history = history)
            session.onEvent(ChannelSelected(Channel.EMAIL))

            polished(session, "hey")

            val entry = history.entries.value.single()
            assertEquals("hey", entry.input)
            assertEquals("polished: hey", entry.output)
            assertEquals(Channel.EMAIL, entry.channel)
        }

    @Test
    fun `a refinement updates the current entry`() =
        runTest(dispatcher) {
            val history = testHistory()
            val session = session(history = history)
            polished(session, "hey")

            session.onEvent(Refine(Refinement.SHORTER))
            advanceUntilIdle()

            assertEquals(listOf("polished: hey (shorter)"), history.outputs())
        }

    @Test
    fun `saving writes the edited output and ignores blank output`() =
        runTest(dispatcher) {
            val history = testHistory()
            val session = session(history = history)
            polished(session, "hey")

            session.onEvent(OutputChanged("edited"))
            session.onEvent(SaveOutput)
            advanceUntilIdle()
            assertEquals(listOf("edited"), history.outputs())

            session.onEvent(OutputChanged("  "))
            session.onEvent(SaveOutput)
            advanceUntilIdle()
            assertEquals(listOf("edited"), history.outputs())
        }

    @Test
    fun `edited output is saved before a new polish and before other text opens`() =
        runTest(dispatcher) {
            val history = testHistory()
            val session = session(history = history)
            polished(session, "one")
            session.onEvent(OutputChanged("one edited"))
            session.onEvent(Polish)
            advanceUntilIdle()
            session.onEvent(OutputChanged("two edited"))

            session.onEvent(Open("three"))
            advanceUntilIdle()

            assertEquals(listOf("two edited", "one edited"), history.outputs())
        }

    @Test
    fun `restoring an entry loads its texts, channel and result`() =
        runTest(dispatcher) {
            val history = testHistory(saved = listOf(savedEntry))
            val session = session(history = history)
            polished(session, "hey")
            session.onEvent(OutputChanged("hey edited"))
            polisher.onPolish = { throw PolishError.Overloaded }
            session.onEvent(Polish)
            advanceUntilIdle()

            session.onEvent(RestoreHistory("saved"))
            advanceUntilIdle()

            val state = session.state.value
            assertEquals("old input", state.input)
            assertEquals("old output", state.output)
            assertEquals(Channel.EMAIL, state.channel)
            val summary = savedEntry.learningSummary
            assertEquals(PolishResult("old output", summary, "pt", true, "model"), state.result)
            assertNull(state.error)
            assertEquals("hey edited", history.outputs().first())
            session.onEvent(ComposerEvent.Retry)
            advanceUntilIdle()
            assertEquals(2, polisher.calls.size)
        }

    @Test
    fun `edits after a restore go to the restored entry`() =
        runTest(dispatcher) {
            val history = testHistory(saved = listOf(savedEntry))
            val session = session(history = history)
            advanceUntilIdle()

            session.onEvent(RestoreHistory("saved"))
            session.onEvent(OutputChanged("new output"))
            session.onEvent(SaveOutput)
            advanceUntilIdle()

            assertEquals(listOf(savedEntry.copy(output = "new output")), history.entries.value)
        }

    @Test
    fun `restoring is ignored while a request runs`() =
        runTest(dispatcher) {
            val session = session(history = testHistory(saved = listOf(savedEntry)))
            session.onEvent(Open("hey"))
            session.onEvent(Polish)
            advanceUntilIdle()

            session.onEvent(RestoreHistory("saved"))

            assertEquals("hey", session.state.value.input)
            assertEquals(Phase.Working(null), session.state.value.phase)
        }

    @Test
    fun `a history save failure is shown but the result is kept`() =
        runTest(dispatcher) {
            val history = testHistory(save = { throw HistoryStoreException("disk full") })
            val session = session(history = history)

            polished(session, "hey")

            val state = session.state.value
            assertEquals("polished: hey", state.output)
            assertEquals(PolishError.HistoryFailed("disk full"), state.error)
            assertEquals(listOf("hey"), history.entries.value.map { it.input })
            session.onEvent(ComposerEvent.Retry)
            advanceUntilIdle()
            assertEquals(1, polisher.calls.size)
        }

    @Test
    fun `an entry whose save failed still takes the refined output`() =
        runTest(dispatcher) {
            var failSave = true
            val history =
                testHistory(save = { if (failSave) throw HistoryStoreException("disk full") })
            val session = session(history = history)
            polished(session, "hey")
            failSave = false

            session.onEvent(ComposerEvent.Refine(Refinement.SHORTER))
            advanceUntilIdle()

            assertEquals(listOf("polished: hey (shorter)"), history.entries.value.map { it.output })
        }
}
