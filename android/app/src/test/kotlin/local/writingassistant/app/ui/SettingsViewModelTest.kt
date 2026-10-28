package local.writingassistant.app.ui

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import local.writingassistant.app.ui.SettingsState.Status
import local.writingassistant.core.PolishError
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val polisher = FakePolishing()
    private val keys = FakeApiKeyStore(key = null)

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    private fun TestScope.viewModel(debugKey: String = ""): SettingsViewModel =
        SettingsViewModel(keys, polisher, debugKey).also { advanceUntilIdle() }

    @Test
    fun `stored key is shown`() =
        runTest(dispatcher) {
            keys.key = "sk-stored"
            val state = viewModel(debugKey = "sk-debug").state.value
            assertEquals("sk-stored", state.key)
            assertTrue(state.hasStoredKey)
        }

    @Test
    fun `debug key prefills an empty store without saving it`() =
        runTest(dispatcher) {
            val state = viewModel(debugKey = "sk-debug").state.value
            assertEquals("sk-debug", state.key)
            assertFalse(state.hasStoredKey)
            assertNull(keys.key)
        }

    @Test
    fun `blank debug key leaves the field empty`() =
        runTest(dispatcher) {
            assertEquals("", viewModel(debugKey = " ").state.value.key)
        }

    @Test
    fun `save stores the trimmed key`() =
        runTest(dispatcher) {
            val vm = viewModel()
            vm.onKeyChange("  sk-new \n")
            vm.save()
            advanceUntilIdle()
            assertEquals("sk-new", keys.key)
            assertEquals(Status.Saved, vm.state.value.status)
        }

    @Test
    fun `blank key is not saved`() =
        runTest(dispatcher) {
            val vm = viewModel()
            vm.onKeyChange("  ")
            vm.test()
            advanceUntilIdle()
            assertNull(keys.key)
            assertEquals(Status.Idle, vm.state.value.status)
        }

    @Test
    fun `test saves then reports success`() =
        runTest(dispatcher) {
            var keyWhenChecked: String? = null
            polisher.onCheckReady = { keyWhenChecked = keys.key }
            val vm = viewModel()
            vm.onKeyChange("sk-new")
            vm.test()
            advanceUntilIdle()
            assertEquals("sk-new", keyWhenChecked)
            assertEquals(Status.TestPassed, vm.state.value.status)
        }

    @Test
    fun `test failure shows the error message`() =
        runTest(dispatcher) {
            polisher.onCheckReady = { throw PolishError.InvalidApiKey }
            val vm = viewModel()
            vm.onKeyChange("sk-bad")
            vm.test()
            advanceUntilIdle()
            assertEquals(
                Status.TestFailed(PolishError.InvalidApiKey.message),
                vm.state.value.status,
            )
        }

    @Test
    fun `clear removes the key`() =
        runTest(dispatcher) {
            keys.key = "sk-stored"
            val vm = viewModel()
            vm.clear()
            advanceUntilIdle()
            assertNull(keys.key)
            assertEquals(SettingsState(status = Status.Cleared), vm.state.value)
        }
}
