package local.writingassistant.app.ui

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withContext
import local.writingassistant.app.ui.ComposerEvent.Cancel
import local.writingassistant.app.ui.ComposerEvent.ChannelSelected
import local.writingassistant.app.ui.ComposerEvent.DismissError
import local.writingassistant.app.ui.ComposerEvent.InputChanged
import local.writingassistant.app.ui.ComposerEvent.OutputChanged
import local.writingassistant.app.ui.ComposerEvent.Polish
import local.writingassistant.app.ui.ComposerEvent.Refine
import local.writingassistant.app.ui.ComposerEvent.RefreshApiKey
import local.writingassistant.app.ui.ComposerEvent.Retry
import local.writingassistant.app.ui.ComposerState.Phase
import local.writingassistant.core.Channel
import local.writingassistant.core.Mode
import local.writingassistant.core.PolishError
import local.writingassistant.core.Refinement
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ComposerViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val polisher = FakePolishing()
    private val settings = FakeAppSettings()
    private val keys = FakeApiKeyStore()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() {
        sessionScope.cancel()
        Dispatchers.resetMain()
    }

    private val sessionScope = CoroutineScope(SupervisorJob() + dispatcher)

    private fun newViewModel(): ComposerViewModel =
        ComposerViewModel(ComposerSession(polisher, settings, keys, testHistory(), sessionScope))

    private fun TestScope.viewModel(): ComposerViewModel =
        newViewModel().also { advanceUntilIdle() }

    @Test
    fun `blank input does not polish`() =
        runTest(dispatcher) {
            val vm = viewModel()
            vm.onEvent(InputChanged("  \n "))
            assertFalse(vm.state.value.canPolish)
            vm.onEvent(Polish)
            advanceUntilIdle()
            assertTrue(polisher.calls.isEmpty())
            assertEquals(Phase.Idle, vm.state.value.phase)
        }

    @Test
    fun `successful polish shows the polished text`() =
        runTest(dispatcher) {
            val vm = viewModel()
            vm.onEvent(InputChanged("hey"))
            vm.onEvent(Polish)
            assertEquals(Phase.Working(null), vm.state.value.phase)
            advanceUntilIdle()
            val state = vm.state.value
            assertEquals(Phase.Idle, state.phase)
            assertEquals("polished: hey", state.output)
            assertEquals("polished: hey", state.result?.polishedText)
            assertEquals(listOf(FakePolishing.Call("hey", Channel.SLACK)), polisher.calls)
        }

    @Test
    fun `error keeps input and output and can be dismissed`() =
        runTest(dispatcher) {
            val vm = viewModel()
            vm.onEvent(InputChanged("hey"))
            vm.onEvent(Polish)
            advanceUntilIdle()
            polisher.onPolish = { throw PolishError.Overloaded }
            vm.onEvent(InputChanged("hey again"))
            vm.onEvent(Polish)
            advanceUntilIdle()
            val state = vm.state.value
            assertEquals(PolishError.Overloaded, state.error)
            assertEquals("hey again", state.input)
            assertEquals("polished: hey", state.output)
            assertEquals(Phase.Idle, state.phase)
            vm.onEvent(DismissError)
            assertNull(vm.state.value.error)
        }

    @Test
    fun `retry runs the failed request again`() =
        runTest(dispatcher) {
            val vm = viewModel()
            polisher.onPolish = { throw PolishError.Timeout(120) }
            vm.onEvent(InputChanged("hey"))
            vm.onEvent(Polish)
            advanceUntilIdle()
            polisher.onPolish = { FakePolishing.result(it) }
            vm.onEvent(Retry)
            advanceUntilIdle()
            assertNull(vm.state.value.error)
            assertEquals("polished: hey", vm.state.value.output)
        }

    @Test
    fun `cancel stops the request and keeps the previous output`() =
        runTest(dispatcher) {
            val gate = CompletableDeferred<Unit>()
            val vm = viewModel()
            polisher.onPolish = {
                gate.await()
                FakePolishing.result(it)
            }
            vm.onEvent(InputChanged("hey"))
            vm.onEvent(Polish)
            advanceUntilIdle()
            vm.onEvent(Cancel)
            assertEquals(Phase.Idle, vm.state.value.phase)
            gate.complete(Unit)
            advanceUntilIdle()
            assertEquals("", vm.state.value.output)
            assertNull(vm.state.value.error)
        }

    @Test
    fun `late result of a cancelled request is ignored after a new polish`() =
        runTest(dispatcher) {
            val first = CompletableDeferred<Unit>()
            val vm = viewModel()
            polisher.onPolish = { text ->
                withContext(NonCancellable) { first.await() }
                FakePolishing.result("stale $text")
            }
            vm.onEvent(InputChanged("one"))
            vm.onEvent(Polish)
            advanceUntilIdle()
            vm.onEvent(Cancel)
            val second = CompletableDeferred<Unit>()
            polisher.onPolish = { text ->
                second.await()
                FakePolishing.result(text)
            }
            vm.onEvent(InputChanged("two"))
            vm.onEvent(Polish)
            advanceUntilIdle()
            first.complete(Unit)
            advanceUntilIdle()
            assertEquals(Phase.Working(null), vm.state.value.phase)
            assertEquals("", vm.state.value.output)
            second.complete(Unit)
            advanceUntilIdle()
            assertEquals(Phase.Idle, vm.state.value.phase)
            assertEquals("polished: two", vm.state.value.output)
        }

    @Test
    fun `refine rewrites the edited output`() =
        runTest(dispatcher) {
            val vm = viewModel()
            vm.onEvent(InputChanged("hey"))
            vm.onEvent(Polish)
            advanceUntilIdle()
            vm.onEvent(OutputChanged("edited"))
            vm.onEvent(Refine(Refinement.SHORTER))
            assertEquals(Phase.Working(Refinement.SHORTER), vm.state.value.phase)
            advanceUntilIdle()
            assertEquals(
                FakePolishing.Call("edited", Channel.SLACK, Refinement.SHORTER),
                polisher.calls.last(),
            )
            assertEquals("edited (shorter)", vm.state.value.output)
            assertEquals(
                "polished: hey",
                vm.state.value.result
                    ?.polishedText,
            )
        }

    @Test
    fun `refine needs output`() =
        runTest(dispatcher) {
            val vm = viewModel()
            vm.onEvent(Refine(Refinement.MORE_CASUAL))
            advanceUntilIdle()
            assertTrue(polisher.calls.isEmpty())
        }

    @Test
    fun `selected channel is persisted and used`() =
        runTest(dispatcher) {
            val vm = viewModel()
            vm.onEvent(ChannelSelected(Channel.FORMAL))
            vm.onEvent(InputChanged("hey"))
            vm.onEvent(Polish)
            advanceUntilIdle()
            assertEquals(Channel.FORMAL, settings.channel)
            assertEquals(Channel.FORMAL, polisher.calls.single().channel)
        }

    @Test
    fun `last channel is restored on start`() =
        runTest(dispatcher) {
            settings.setLastChannel(Mode.WORK, Channel.AI_PROMPT)
            assertEquals(Channel.AI_PROMPT, viewModel().state.value.channel)
        }

    @Test
    fun `a channel picked before the restore finishes wins`() =
        runTest(dispatcher) {
            settings.setLastChannel(Mode.WORK, Channel.AI_PROMPT)
            val vm = newViewModel()
            vm.onEvent(ChannelSelected(Channel.TALKING_POINTS))
            advanceUntilIdle()
            assertEquals(Channel.TALKING_POINTS, vm.state.value.channel)
        }

    @Test
    fun `missing key disables polish until a key is saved`() =
        runTest(dispatcher) {
            keys.key = null
            val vm = viewModel()
            vm.onEvent(InputChanged("hey"))
            assertTrue(vm.state.value.needsApiKey)
            vm.onEvent(Polish)
            advanceUntilIdle()
            assertTrue(polisher.calls.isEmpty())
            keys.key = "sk-new"
            vm.onEvent(RefreshApiKey)
            advanceUntilIdle()
            assertTrue(vm.state.value.canPolish)
        }

    @Test
    fun `missing key error asks for a key`() =
        runTest(dispatcher) {
            val vm = viewModel()
            polisher.onPolish = { throw PolishError.MissingApiKey }
            vm.onEvent(InputChanged("hey"))
            vm.onEvent(Polish)
            advanceUntilIdle()
            assertTrue(vm.state.value.needsApiKey)
            assertEquals(PolishError.MissingApiKey, vm.state.value.error)
        }
}
