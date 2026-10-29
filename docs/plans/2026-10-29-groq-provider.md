# Groq as a second LLM provider for the Android app

## Context

The Android app (`android/`, merged to `main` in PR #12 as `142256d`) only talks to the Anthropic API with the user's own key.
`docs/llm-backend-options.md` (written 2026-10-29, not committed yet) compared alternatives. Its
best free option is **Groq's free tier**: no inference data retained by default, about 65 of our
requests per day.

**User decision (2026-10-29):** offer Groq as a provider option in the app. There's no separate
comparison or evaluation step; the user judges Groq by using it.

**Outcome:** Settings has an Anthropic | Groq choice, each with its own encrypted key, and
Anthropic stays the default.

## Design

### `:core`
- **Rename `ClaudeClient` → `LlmClient`** (`Contracts.kt`), and `FakeClaudeClient` →
  `FakeLlmClient` (test fixtures). The interface stays the same: `run(prompt, model, timeout)`
  and `checkAvailable()`. The old name goes; no alias.
- **`Provider` enum** in `Contracts.kt` with `ANTHROPIC` and `GROQ`. Each entry has `id` (used as
  the storage key), `displayName`, `keyUrl` (console.anthropic.com / console.groq.com/keys) and a
  `Models(small, large)` pair:
  - Anthropic: `small = "claude-haiku-4-5-20251001"`, `large = "claude-sonnet-5-5"` (unchanged).
  - Groq: model IDs looked up in the Groq console at implementation time. Both models must be on
    the free tier, handle Spanish and Catalan, and fit in 8K tokens/min. Candidates are a Llama 3.x
    instant model (small) and `openai/gpt-oss-120b` or a Llama 70B model (large).
- **Routing by tier.** `ModelRouting.pickModel(text): String` becomes `pickTier(text): ModelTier`
  (`SMALL`/`LARGE`), using the same heuristic and the same tests rewritten to assert tiers. The
  `HAIKU_MODEL`/`SONNET_MODEL` constants move into `Provider.ANTHROPIC.models`. Update the
  KDoc's "mirrors `ModelRouting.swift`" note: the heuristic still mirrors Swift, only the return
  type differs.
- **`PolishService` takes a backend instead of a fixed client:**
  `PolishService(backend: suspend () -> Backend, prompts, timeout)`, where
  `Backend(client: LlmClient, models: Models)`. `polish` and `refine` resolve the backend once
  per call and pick `models.forTier(ModelRouting.pickTier(input))`. `modelUsed` reports the real
  model ID.
  - A secondary constructor `PolishService(client, prompts)` uses Anthropic's models, so existing
    pipeline tests stay readable.
- **Shared HTTP plumbing.** Move from `AnthropicClient.kt` into an `internal` file
  `api/HttpTransport.kt` without behaviour change:
  - the `execute` coroutine wrapper with cancellation
  - `clientFor(timeout)`
  - `Redactor`
  - `ioFailure`
  - `isWellFormedKey`
  This is a move rather than a new abstraction: a second client would otherwise copy about 80
  lines of cancellation and redaction code.
- **`api/GroqClient.kt`**: an `LlmClient` doing `POST https://api.groq.com/openai/v1/chat/completions`
  (OpenAI-compatible) with `Authorization: Bearer <key>`.
  - **Request:** one user message; `max_completion_tokens` sized like Anthropic's (capped at the
    model's limit); `response_format: {"type": "json_object"}` for polish calls.
  - **Reasoning:** for a reasoning model like gpt-oss, set the lowest reasoning effort. This
    matches turning thinking off on Claude.
  - **To verify against Groq's docs at implementation:** parameter names, JSON mode for both
    models, how refine prompts (which also return JSON) behave, and error bodies.
  - **Errors:**
    - `finish_reason: "length"` → `OutputTooLong`
    - 401/403 → `InvalidApiKey`
    - 429 and 413 (over the tokens-per-minute limit) → `Overloaded`
    - 5xx → `Overloaded` or `ApiFailed`, whichever matches Anthropic's mapping
    - empty `choices` → `BadFormat`
  - `checkAvailable()` sends a 1-token request to the small model.
  - The key is redacted from every error, as in `AnthropicClient`.
- **Provider-neutral error messages** in `PolishError` (`Contracts.kt:81-126`). For example:
  - "Add your API key in Settings to start."
  - "The API key was rejected. Check it in Settings."
  - "The AI service is busy or you've hit its rate limit. Try again shortly."
  - "Couldn't reach the AI service."
  `NoCredits` can only come from Anthropic, so it keeps naming the Anthropic Console. Update
  `ContractsTests` to match.
- **Live test:**
  - `LivePolishTest` gets Groq cases that are skipped (JUnit `assumeTrue`) when there's no
    `GROQ_API_KEY`. The Anthropic cases get the same treatment.
  - The `liveTest` task in `core/build.gradle.kts` reads both keys the way it reads
    `ANTHROPIC_API_KEY` today, and runs when either key is set.
  - CI still sets neither key.

### `:app`
- **`ApiKeyStore` is keyed by provider:** `read(provider)`, `write(provider, key)`,
  `clear(provider)`. `KeystoreApiKeyStore` keeps one AES-GCM Keystore key and stores each provider
  under `"${provider.id}_api_key"`. Anthropic keeps the existing `anthropic_api_key` preference
  name, so an already-saved key survives the update.
- **`AppSettings` gains `provider(): Provider`** (default `ANTHROPIC`) and `setProvider(provider)`
  in `DataStoreAppSettings`.
- **`DefaultAppGraph`** (`AppGraph.kt`) builds both clients once and passes `PolishService` a
  backend lambda. The lambda reads `settings.provider()` on each call and returns that provider's
  client and models. Each client reads its own key from `apiKeyStore.read(provider)`.
- **`ComposerSession`** checks for a missing key against the current provider (line ~74).
- **Settings screen and `SettingsViewModel`:**
  - Material3 segmented buttons for Anthropic | Groq sit at the top. Choosing one saves the
    provider right away and loads that provider's key into the field.
  - The key label, the "why" text and the link change per provider. The Groq text says plainly
    that text is sent to Groq.
  - Save, Test and Clear act on the selected provider. The well-formed check comes from
    `HttpTransport`.
- **Debug key prefill:** add `DEBUG_GROQ_API_KEY` from `GROQ_API_KEY` in `local.properties`, next
  to `DEBUG_API_KEY` in `app/build.gradle.kts`. Release builds embed `""`, as before.
- **Strings** (`res/values/strings_ui.xml`): replace Anthropic-only wording (`composer_needs_key`,
  `settings_api_key`, `settings_why`) with neutral or per-provider strings.

### Docs
- `README.md` Android section: how to choose a provider and where to get a Groq key.
- `docs/architecture.md`:
  - `LlmClient`, `Provider` and the tier routing.
  - The Kotlin routing returns a tier where Swift returns a model ID.
  - The shared prompts must produce valid JSON on every provider.
- Commit `docs/llm-backend-options.md` with this plan, noting that Groq is now offered in the app.

## Execution

New branch `feat/NOJIRA-000_android_groq` from an up-to-date `origin/main`, with the PR into `main`.
Same pattern as the Android plan: the main session does the
contract commit, then parallel worktree workers branch from the feature branch.

1. **Main session, contract commit:**
   - the `LlmClient` rename
   - `Provider`, `Models`, `ModelTier`, `Backend` and the `pickTier` signature
   - the `PolishService` constructor change, with the old behaviour behind the secondary
     constructor
   - `HttpTransport` extracted
   - the `ApiKeyStore`/`AppSettings` signatures with stub implementations, and `GroqClient` as a
     stub
   Everything must compile and tests stay green.
2. **Wave 1, in parallel:**

   | Worker | Owns | Done when |
   |---|---|---|
   | `core` | `GroqClient` + MockWebServer tests, `pickTier`, the `PolishService` backend, neutral `PolishError` messages and their tests, a Groq case in `LivePolishTest` (skipped without `GROQ_API_KEY`) | `:core:test` green |
   | `app` | per-provider `KeystoreApiKeyStore`, provider in `DataStoreAppSettings`, `AppGraph` wiring, Settings UI/VM, `ComposerSession` key check, strings, debug Groq key | `:app:testDebugUnitTest` green, Settings screenshots on the emulator |

3. **Wave 2, `docs` worker:** README, `docs/architecture.md`, and committing
   `docs/llm-backend-options.md`.
4. **Main session:** run a code-review subagent and fix workers, do the emulator check, and open a
   draft PR into `main`.

**Constraints for every worker** (carried over from the Android plan):
- Never read or print `android/local.properties`, and filter `sk-ant`/`gsk_` from all output.
- Tests never assert or print key values.
- No new dependencies.
- Kotlin warnings are errors, and lint and ktlint must be clean.
- Commit subjects use `type(NOJIRA-000): …`.

## Before you start (user)
- Done (2026-10-29): the Groq key is already in `android/local.properties` as `GROQ_API_KEY`.
  Workers still never read or print that file.
- Rotate the Anthropic key, because part of it was printed in an earlier session, and add credits.
  This is only needed to check that the Anthropic path still works.

## Verification
- `cd android && JAVA_HOME=$(/usr/libexec/java_home -v 21) ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ./gradlew :core:test :app:testDebugUnitTest lint ktlintCheck :app:assembleDebug`
  is green with zero warnings.
- **`GroqClient` MockWebServer tests:**
  - success
  - `finish_reason: length`
  - 401
  - 429 and 413
  - 5xx
  - empty choices
  - malformed body
  - timeout
  - cancellation cancels the call
  - the key never appears in error messages
- **Other unit tests:**
  - `PolishService`: the backend's models are used per tier, and `modelUsed` reports them.
  - `KeystoreApiKeyStore`: keys for the two providers are independent, and an existing
    `anthropic_api_key` value is still read.
  - `SettingsViewModel`: switching provider loads that provider's key, and Test checks the
    selected provider.
- `./gradlew :core:liveTest` passes for each provider whose key is set. The Groq case checks that
  short English, Spanish and Catalan texts come back as valid JSON.
- **Emulator (release build, no keys embedded):**
  - Choose Groq, enter the key, Test passes.
  - Polish a short English text and a Catalan text in the app.
  - Polish through the text-selection sheet with Replace.
  - Switch back to Anthropic: its key is still there.
