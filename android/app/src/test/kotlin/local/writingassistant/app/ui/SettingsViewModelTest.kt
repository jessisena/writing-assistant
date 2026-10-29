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
import local.writingassistant.core.Provider
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
    private val settings = FakeAppSettings()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    private fun TestScope.viewModel(
        debugKey: String = "",
        debugGroqKey: String = "",
    ): SettingsViewModel {
        val debugKeys = mapOf(Provider.ANTHROPIC to debugKey, Provider.GROQ to debugGroqKey)
        return SettingsViewModel(keys, settings, polisher, debugKeys).also { advanceUntilIdle() }
    }

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
                Status.Failed(PolishError.InvalidApiKey.message),
                vm.state.value.status,
            )
        }

    @Test
    fun `a key with characters that can't go in a header is not saved or tested`() =
        runTest(dispatcher) {
            val malformed = listOf("sk-ant-key\u200B", "\u201Csk-ant-key\u201D", "sk-ant\n-key")
            for (key in malformed) {
                val vm = viewModel()
                var checked = false
                polisher.onCheckReady = { checked = true }

                vm.onKeyChange(key)
                vm.save()
                advanceUntilIdle()
                val afterSave = vm.state.value.status
                vm.test()
                advanceUntilIdle()

                val expected = Status.Failed(PolishError.MalformedApiKey.message)
                assertEquals(expected, afterSave)
                assertEquals(expected, vm.state.value.status)
                assertFalse((vm.state.value.status as Status.Failed).message.contains("sk-ant"))
                assertNull(keys.key)
                assertFalse(checked)
            }
        }

    @Test
    fun `a key storage failure on save is shown`() =
        runTest(dispatcher) {
            val failure = PolishError.KeyStorageFailed("ProviderException")
            val vm =
                SettingsViewModel(
                    FailingKeyStore(failure),
                    settings,
                    polisher,
                    emptyMap(),
                ).also { advanceUntilIdle() }

            assertEquals(Status.Failed(failure.message), vm.state.value.status)
            vm.onKeyChange("sk-ant-key")
            vm.save()
            advanceUntilIdle()

            assertEquals(Status.Failed(failure.message), vm.state.value.status)
            assertFalse(vm.state.value.hasStoredKey)
        }

    @Test
    fun `an unexpected failure is shown instead of crashing`() =
        runTest(dispatcher) {
            polisher.onCheckReady = { throw IllegalStateException("sk-ant-secret") }
            val vm = viewModel()
            vm.onKeyChange("sk-ant-key")
            vm.test()
            advanceUntilIdle()

            val status = vm.state.value.status
            assertEquals(
                Status.Failed(PolishError.Unexpected("IllegalStateException").message),
                status,
            )
            assertFalse((status as Status.Failed).message.contains("sk-ant"))
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

    @Test
    fun `the saved provider and its key are loaded`() =
        runTest(dispatcher) {
            settings.provider = Provider.GROQ
            keys.key = "sk-ant-fake"
            keys.keys[Provider.GROQ] = "groq-stored"

            val state = viewModel(debugKey = "sk-debug").state.value

            assertEquals(Provider.GROQ, state.provider)
            assertEquals("groq-stored", state.key)
            assertTrue(state.hasStoredKey)
        }

    @Test
    fun `choosing a provider saves it and shows its key`() =
        runTest(dispatcher) {
            keys.key = "sk-ant-fake"
            keys.keys[Provider.GROQ] = "groq-stored"
            val vm = viewModel()
            vm.onKeyChange("typed but not saved")

            vm.selectProvider(Provider.GROQ)
            advanceUntilIdle()

            assertEquals(Provider.GROQ, settings.provider)
            assertEquals(
                SettingsState(provider = Provider.GROQ, key = "groq-stored", hasStoredKey = true),
                vm.state.value,
            )
            vm.selectProvider(Provider.ANTHROPIC)
            advanceUntilIdle()
            assertEquals(Provider.ANTHROPIC, settings.provider)
            assertEquals("sk-ant-fake", vm.state.value.key)
        }

    @Test
    fun `choosing a provider without a stored key shows its debug key`() =
        runTest(dispatcher) {
            keys.key = "sk-ant-fake"
            val vm = viewModel(debugKey = "sk-debug", debugGroqKey = "groq-debug")

            vm.selectProvider(Provider.GROQ)
            advanceUntilIdle()

            assertEquals("groq-debug", vm.state.value.key)
            assertFalse(vm.state.value.hasStoredKey)
            assertNull(keys.keys[Provider.GROQ])
        }

    @Test
    fun `choosing a provider resets the status`() =
        runTest(dispatcher) {
            val vm = viewModel()
            vm.onKeyChange("sk-new")
            vm.save()
            advanceUntilIdle()

            vm.selectProvider(Provider.GROQ)
            advanceUntilIdle()

            assertEquals(Status.Idle, vm.state.value.status)
        }

    @Test
    fun `save and clear act on the selected provider only`() =
        runTest(dispatcher) {
            keys.key = "sk-ant-fake"
            val vm = viewModel()
            vm.selectProvider(Provider.GROQ)
            advanceUntilIdle()

            vm.onKeyChange("groq-new")
            vm.save()
            advanceUntilIdle()
            assertEquals("groq-new", keys.keys[Provider.GROQ])
            assertEquals("sk-ant-fake", keys.key)

            vm.clear()
            advanceUntilIdle()
            assertNull(keys.keys[Provider.GROQ])
            assertEquals("sk-ant-fake", keys.key)
            assertEquals(
                SettingsState(provider = Provider.GROQ, status = Status.Cleared),
                vm.state.value,
            )
        }

    @Test
    fun `test stores the selected provider's key before checking it`() =
        runTest(dispatcher) {
            keys.key = "sk-ant-fake"
            var checked: Pair<Provider, String?>? = null
            polisher.onCheckReady = { checked = settings.provider to keys.keys[Provider.GROQ] }
            val vm = viewModel()
            vm.selectProvider(Provider.GROQ)
            advanceUntilIdle()

            vm.onKeyChange("groq-new")
            vm.test()
            advanceUntilIdle()

            assertEquals(Provider.GROQ to "groq-new", checked)
            assertEquals("sk-ant-fake", keys.key)
            assertEquals(Status.TestPassed, vm.state.value.status)
        }
}
