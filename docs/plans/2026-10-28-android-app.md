# Android version of Writing Assistant

## Context

Writing Assistant is a native macOS SwiftUI app (~12.5k lines incl. tests). You paste text, pick a
channel, and one Claude call returns polished text plus a learning summary. The user wants an
Android version, built the simplest way possible.

The main blocker is the backend. The Mac app runs the `claude` CLI as a subprocess on subscription
OAuth (`ClaudeCLI.swift`), which can't happen on Android. **Decision (user):** call the Anthropic
Messages API directly with the user's own API key. Code lives in `android/` in this repo.

Toolchain: `java` is present. There is no Android SDK, adb or Gradle, and no Android Studio.

## Options assessed

| Option | Effort | Feasibility | Verdict |
|---|---|---|---|
| **Native Kotlin + Jetpack Compose, API key** | Medium. Port ~500 lines of core logic, write a new UI | High. Standard stack, and Android has a text-selection hook that matches the Services menu | **Chosen** |
| PWA / web page calling the API from the browser | Low | Medium. The key sits in browser storage, there's no text-selection integration, and the app already left PWA once | Fallback only |
| Swift SDK for Android to reuse `WritingAssistantCore` | High | Low. Core depends on Foundation `Process` and file paths, the UI still has to be Kotlin, and there's JNI glue and an immature toolchain | Rejected |
| Flutter / Kotlin Multiplatform rewrite | High | High, but it rewrites the Mac app too, or keeps two codebases anyway | Rejected |
| Relay to the Mac's CLI over Tailscale | Low–medium | Medium. The Mac has to be awake, and it brings back a server | Rejected by user |

## What carries over and what doesn't

**Ported to Kotlin (pure logic, no Android deps):**
- `ModelRouting.swift` (51 lines): `pickModel`, word/non-ASCII/romance-stopword heuristic
- `JSONExtraction.swift` (24): find the JSON object in model output
- `PolishService.swift` (203): validate → route → assemble → call → parse → enforce the
  `learningSummary == null when wasTranslated` invariant
- `Contracts.swift` types: `Channel`, `Refinement`, `PolishResult`, learning summary, `PolishError`
- The `assemble(for:)` part of `PromptStore.swift` (read-only, from bundled assets)

**Shared without copying:** point Gradle `assets.srcDirs` at
`Sources/WritingAssistantCore/Resources/Prompts/`, so both apps read the same prompt files.

**Replaced:** `ClaudeCLI` / `ClaudeBinaryLocator` become `AnthropicClient`, a single `POST
/v1/messages` call using OkHttp + kotlinx.serialization (two small, well-known dependencies for
one endpoint). The client sends no thinking parameter, so extended thinking stays off, the same as
`MAX_THINKING_TOKENS=0`.

**Left out of the MVP:** prompt editor, theme palettes, rich-text editing, diff view, history, and
the learning-log file. Output is shown as the Markdown subset with basic formatting.

**Android equivalent of the Services menu:** an `ACTION_PROCESS_TEXT` activity that adds
"Polish" to the text-selection menu in any app, plus an `ACTION_SEND` text share target. Unlike
macOS Services, PROCESS_TEXT can return the replacement text, but only when the caller allows
editing.

## UX: how the app is used on the phone

On the phone you write inside other apps (Slack, Gmail, WhatsApp, Docs), not in a separate
editor. The main path is therefore **polishing in place without leaving the app**. The full
app screen is secondary.

### Flow 1, the main one: select, then Polish (text-selection menu)
1. In Slack you type a message, long-press, **Select all**, and pick **Polish** in the floating
   selection menu (⋮ overflow on some keyboards and apps).
2. A **bottom sheet** slides up over Slack. It's a translucent activity, so Slack stays visible
   behind it. The sheet already has your text in it and shows the channel chips, with the
   last-used channel preselected.
3. Tap **Polish**. The sheet shows a progress state with Cancel. Requests take ~8–20 s, and the
   sheet can be dismissed; the result is kept for later.
4. The result appears in the sheet with three actions:
   - **Replace**: closes the sheet and swaps the selected text in Slack for the polished
     version. Shown only when the app allows editing.
   - **Copy**: copies the formatted text (HTML plus plain-text fallback), then closes.
   - **Shorter / More casual / More formal**: refine again in place.
   The Learning Summary is a collapsible row under the result, collapsed by default.

```
┌─────────────────────────────┐
│  Slack (dimmed behind)      │
├─────────────────────────────┤
│ ▔▔▔                         │
│ Slack · Slack informal ·    │  ← channel chips (scroll)
│ Formal · Talking points …   │
│ ┌─────────────────────────┐ │
│ │ hey can u check the PR  │ │  ← input, editable
│ │ before tomorow?         │ │
│ └─────────────────────────┘ │
│        [ Polish ]           │
├─ after result ──────────────┤
│ ┌─────────────────────────┐ │
│ │ Hey, could you check    │ │  ← polished, editable
│ │ the PR before tomorrow? │ │
│ └─────────────────────────┘ │
│ ▸ What changed (2 tips)     │
│ [Shorter][Casual][Formal]   │
│   [ Copy ]   [ Replace ]    │
└─────────────────────────────┘
```

### Flow 2: Share
If an app doesn't show "Polish" in its selection menu, use **Share → Writing Assistant**. It
opens the same bottom sheet. There's no Replace here (Android doesn't support it for shares), so
Copy is the action.

### Flow 3: The app itself (launcher icon)
- One full-screen composer: the same layout as the sheet, but taller, with a top bar that has
  **History** (later phase) and **Settings**.
- For longer writing (talking points, formal docs, AI prompts) or pasting from anywhere.

### Settings screen
- API key, masked, with a Test button. Default channel. Links to the bundled prompts, read-only
  in the MVP.

### First run
The first time you open the app or the sheet, it asks for the API key once, with a short "why"
line and a link to console.anthropic.com. Polish stays disabled until a test call succeeds.

### Errors
Errors show as an inline banner in the sheet or screen, with a retry button and a plain
message (invalid key, no connection, overloaded, timed out). Your input is never lost.

### Look
Material 3 with the existing Writing Desk palette colours (ink/paper/desk tokens from
`ThemePalette.swift`) as a static light/dark colour scheme. No theme picker in the MVP.

## Plan (save as `docs/plans/2026-10-28-android-app.md` when executing)

### Phase 0: Toolchain, API key and scaffold
- **API key (from you, before development starts).** Unit tests never need it: they use fakes and
  MockWebServer. It's needed for the live smoke test and for manual testing on the emulator, so
  getting it now means nothing blocks later. To provide it:
  - Create a dedicated key in console.anthropic.com with a monthly spend limit (e.g. $10), so it
    can be revoked on its own.
  - Don't paste it in chat. Add `ANTHROPIC_API_KEY=sk-ant-…` to `android/local.properties`.
    That file is gitignored by default for Android projects, and Phase 0 also checks the repo's
    `.gitignore`.
  - Debug builds read it into `BuildConfig` to prefill Settings. Release builds never embed it
    and always use the in-app entry.
  - A `:core` live smoke test, `./gradlew :core:liveTest`, reads it from the environment or
    `local.properties`. It sends one short English and one non-English text through the real
    API, checking prompts, routing and JSON parsing before any UI exists. It's skipped when no
    key is present, so CI doesn't need the secret.
- Install the Android command-line tools (`brew install --cask android-commandlinetools`),
  `sdkmanager` the platform, build-tools and an emulator image, and check the JDK version. These
  are large downloads, so confirm before installing.
- `android/` Gradle project (Kotlin DSL, version catalog). Two modules:
  - `:core`: pure Kotlin/JVM, holds the ported logic, fast JVM unit tests
  - `:app`: Compose UI, `AnthropicClient`, key storage, intents
- Look up current stable versions of AGP, Kotlin, Compose BOM, OkHttp and kotlinx.serialization
  at implementation time, pinned to releases at least 7 days old.
- ktlint or detekt plus Android lint, with zero warnings. Add a CI job in `.github/workflows/ci.yml`
  (ubuntu: `./gradlew :core:test :app:lint :app:assembleDebug`). Actions pinned by SHA, scanned
  with zizmor.

### Phase 1: Port the core (TDD)
- Port the Swift tests first (`RoutingTests`, `PipelineTests`, `RefinementTests`,
  `ContractsTests`) as JUnit tests against a fake `ClaudeClient` interface. That interface mirrors
  `ClaudeRunning`: `suspend fun run(prompt, model, timeout): String`.
- Then port the logic until the tests pass. Keep the model constants identical to start. Via the
  API (no CLI overhead), Haiku 5.5's latency may be fine, so re-measure before changing routing.

### Phase 2: API client and key storage
- `AnthropicClient`: headers `x-api-key` and `anthropic-version`, prompt as one user message,
  `max_tokens` sized for the output. Map 401 to missing/invalid key, 429/529 to overloaded, and
  timeouts and network errors to `PolishError` cases with actionable messages.
- Store the API key (entered in Settings, or prefilled from `BuildConfig` in debug) encrypted with
  an Android Keystore-backed key in DataStore. Never log it.
- Run `:core:liveTest` against the real API using the Phase 0 key.
- Test with OkHttp `MockWebServer`: success, malformed JSON, 401, 429, timeout.

### Phase 3: UI (one composer used as both sheet and full screen, plus settings)
- Build a single `Composer` composable as described in the UX section. The full-screen app and the
  bottom sheet both host it, so the logic lives in one `ComposerViewModel`.
- Composer: multiline input, channel chips (the 6 channel files), last-used channel remembered,
  Polish button with a loading state and cancel (coroutine job, with a generation check like
  `RequestRunner.swift`).
- Result: polished text with formatting (Markdown → `AnnotatedString` for bold, italic, code,
  links and bullets), a Copy button (`ClipData.newHtmlText` with a plain-text fallback), and a
  Learning Summary card. The three refinement buttons work too, since their prompts already exist.
- Settings: API key entry and validation (a cheap test call).

### Phase 4: System integration
- `ProcessTextActivity` (PROCESS_TEXT) and `ShareActivity` (ACTION_SEND text/plain) are
  translucent activities that host the composer in a `ModalBottomSheet`, prefilled with the text.
- Replace returns `EXTRA_PROCESS_TEXT` via `setResult` and is hidden when
  `EXTRA_PROCESS_TEXT_READONLY` is set or the sheet was opened from Share.
- Dismissing the sheet mid-request keeps the result in the ViewModel's scope, so opening the
  app again shows it.

### Distribution
- A signed debug or release APK, sideloaded via adb or a file download. No Play Store.

## Execution: main session plus parallel subagents

Feature branch: `feat/NOJIRA-000_android_app`, from `main`. The main session orchestrates and
merges. Workers are subagents, each in its own git worktree, branched from the feature branch
(`git switch -c feat/NOJIRA-000_android_<stream> feat/NOJIRA-000_android_app`, not
`origin/main`).

### Step 1: Main session, serial (Phase 0 + contract)
- Install the toolchain (after your confirmation), and set up the API key in `local.properties`.
- Scaffold `android/`:
  - `settings.gradle.kts` and the version catalog, with **every** dependency for all streams
    declared up front, so workers never edit shared build files
  - module build files and `AndroidManifest.xml`, with all activities declared
  - lint config and the CI job
- **Contract commit.** It holds:
  - `:core` types: `Channel`, `Refinement`, `PolishResult`, `LearningSummary`, `PolishError`
  - the `ClaudeClient` and `Polishing` interfaces
  - a `FakeClaudeClient` for tests
  - stub `ComposerViewModel` state and events
  - the `ApiKeyStore` interface
  - empty activity classes
  All of it must compile. The build must be green before any worker starts.

### Step 2: Wave 1, three workers in parallel
Each worker owns its files, so merges don't conflict.

| Worker | Owns | Done when |
|---|---|---|
| `core` | `:core` logic and JUnit ports of the Swift tests, `liveTest` | `:core:test` green, `liveTest` passes with the key |
| `client` | `AnthropicClient`, Keystore/DataStore `ApiKeyStore`, MockWebServer tests | `:app:testDebugUnitTest` green for client and key store |
| `ui` | `Composer` composable, `ComposerViewModel`, Settings screen, theme colours, Markdown → `AnnotatedString`, built against `FakeClaudeClient` | Unit tests for the ViewModel and Markdown parser green, emulator screenshots |

The main session merges each branch as soon as it finishes, then runs
`./gradlew :core:test :app:testDebugUnitTest :app:lint`.

### Step 3: Wave 2, two workers in parallel
| Worker | Owns | Done when |
|---|---|---|
| `intents` | `ProcessTextActivity`, `ShareActivity`, bottom-sheet host, Replace result | Instrumented or Robolectric tests for Replace/read-only, manual check on the emulator |
| `docs` | `README.md` Android section, `docs/architecture.md` (Android layout, "change logic in both apps" note), CHANGELOG entry via the conventional commit | Docs match the code |

### Step 4: Main session (integration and review)
- Wire the real `AnthropicClient` into the app, and run the full verification below on the
  emulator.
- Run a code-review subagent over the whole diff. Fixes go to parallel fix workers (one per
  area), which the main session merges.
- Final checks green, zero warnings, then open a draft PR.

## Effort estimate

About 1.5–2k lines of Kotlin. Most of the time goes to Wave 1, where the three workers run at
the same time.

## Risks

- **Cost:** the API is billed per token and doesn't use the subscription. Prompt ~1.2k words plus
  input is about 2–3k tokens in, ~0.5k out, roughly $0.01–0.02 per Sonnet call. Prompt caching
  on the static instructions can cut this.
- **Prompt drift:** none while assets point at the shared directory. Swift-only prompt changes
  automatically apply to Android.
- **Logic drift:** the routing and invariant code is duplicated in two languages. Ported tests
  keep the two in step. Changes need to be made in both, so note this in `docs/architecture.md`.

## Verification
- `cd android && ./gradlew :core:test`: ported routing, pipeline and invariant tests pass.
- `./gradlew :app:testDebugUnitTest`: MockWebServer client tests pass.
- `./gradlew :app:lint assembleDebug`: zero warnings.
- Install on an emulator (`adb install`). Enter the key, polish short English text (Haiku, with a
  learning summary) and non-English text (Sonnet, no summary). Check that cancel works.
- Select text in an editable field (e.g. the Gmail compose box), then "Polish": the sheet opens
  prefilled, and Replace swaps the text in place. Do the same in a read-only page (Chrome): there
  Replace is hidden and Copy works.
- Share text from another app: the sheet opens with Copy only. Copy into Slack Android and check
  the formatting.
