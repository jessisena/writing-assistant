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
import local.writingassistant.app.ui.ComposerEvent.Cancel
import local.writingassistant.app.ui.ComposerEvent.ChannelSelected
import local.writingassistant.app.ui.ComposerEvent.DismissError
import local.writingassistant.app.ui.ComposerEvent.Open
import local.writingassistant.app.ui.ComposerEvent.Polish
import local.writingassistant.app.ui.ComposerState.Phase
import local.writingassistant.core.Channel
import local.writingassistant.core.PolishError
import local.writingassistant.core.Provider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

    private fun session() =
        ComposerSession(polisher, FakeAppSettings(), FakeApiKeyStore(), sessionScope)

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
                ComposerSession(polisher, FakeAppSettings(), FailingKeyStore(failure), sessionScope)

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
                object : AppSettings {
                    override suspend fun lastChannel(): Channel? = throw IOException("disk")

                    override suspend fun setLastChannel(channel: Channel) =
                        throw IOException("disk")

                    override suspend fun provider(): Provider = Provider.ANTHROPIC

                    override suspend fun setProvider(provider: Provider) = Unit
                }
            val session = ComposerSession(polisher, settings, FakeApiKeyStore(), sessionScope)
            advanceUntilIdle()

            assertEquals(PolishError.Unexpected("IOException"), session.state.value.error)
            session.onEvent(DismissError)
            session.onEvent(ChannelSelected(Channel.FORMAL))
            advanceUntilIdle()
            assertEquals(Channel.FORMAL, session.state.value.channel)
            assertEquals(PolishError.Unexpected("IOException"), session.state.value.error)
        }
}
