# Android: preferences, prompt editing, new modes/refinements, palettes, history

## Context

The Android app (Kotlin + Compose, `android/`) has a composer, a PROCESS_TEXT/share bottom sheet
and a Settings screen that only holds the provider and API key. You asked for: a switch to turn off
the English learning summary, prompt editing, "More diplomatic"/"More assertive" refinements,
per-mode enable/disable, new modes for personal mobile use, a colour palette setting and access to
history. Decisions taken with you: the new modes are **Email**, **Personal message** and
**Proofread only**; new modes and refinements go to **Android + Mac** (shared `Prompts` folder and
both enums); palettes are **Writing Desk / Lagoon / Sepia (Mac presets) + System (Material You)**.

Branch `feat/NOJIRA-000_android_settings_history`; this plan is copied to
`docs/plans/2026-10-29-android-settings-history.md` first. Same execution style as earlier work:
I commit the contracts, then parallel worktree subagents, then review and merge.

## 1. Shared contracts (main session, one commit)

- **Swift** `Sources/WritingAssistantCore/Contracts.swift`: `Channel` gains `email`,
  `personalMessage = "personal_message"`, `proofread`
  (display "Email" / "Personal message (text, WhatsApp)" / "Proofread only";
  short "Email" / "Personal" / "Proofread"). `Refinement` gains
  `moreDiplomatic = "more_diplomatic"`, `moreAssertive = "more_assertive"`. Update
  `Tests/WritingAssistantCoreTests/ContractsTests.swift` expectations. Mac `PromptStore.seedMissing`
  already seeds new bundled files on next launch, so no migration.
- **Kotlin** `android/core/.../Contracts.kt`: same cases, same ids; add
  `PromptFile.all` (global, channels, refinements, in that order, like Swift `allCases`); update
  `ContractsTest.kt`.
- **Prompt files** in `Sources/WritingAssistantCore/Resources/Prompts/`: `channels/email.txt`,
  `channels/personal_message.txt`, `channels/proofread.txt`, `refinements/more_diplomatic.txt`,
  `refinements/more_assertive.txt`, written in the style of the existing files (short rules, "Never
  use em dashes", keep emoji/Markdown, don't add facts). Proofread: minimal edits, keep voice,
  length and structure, no added bullets. Diplomatic: soften demands into requests, acknowledge
  the other view, keep the ask. Assertive: direct asks, drop hedges/apologies, clear owner and
  deadline, stay respectful.
- **Interfaces** (signatures only, bodies `TODO()` where new):
  - `Polishing.polish(text, channel, learningSummary: Boolean = true)`.
  - `AppSettings` adds flows + setters: `disabledChannels: Flow<Set<Channel>>`,
    `learningSummaryEnabled: Flow<Boolean>` (default true), `palette: Flow<PalettePreset>`
    (default `WRITING_DESK`).
  - core `HistoryEntry` (@Serializable, mirrors Swift `HistoryEntry`; unknown channel id → OTHER)
    and `HistoryStore(file: File, limit = 50)` with `load()` / `save(entries)`.
  - core `PromptOverrideStore(directory: File, defaults: PromptReading) : PromptReading` with
    `isCustomized(file)`, `save(file, text)`, `reset(file)`.

## 2. Worker A — core (`android/core`, JVM tests)

- `PolishService.polish(..., learningSummary = false)`: appends a note telling the model to skip
  Step 4 and set `learning_summary` to null (saves tokens and time), and forces the summary to null
  in `parse` regardless of the reply. Tests in `PolishServiceTest.kt` (prompt contains the note;
  summary dropped even if the model returns one).
- `HistoryStore`: port of `Sources/WritingAssistantCore/HistoryStore.swift` — newest first, cut to
  limit, atomic write (temp file + rename), corrupt file moved to `history.corrupt.json` and a
  `PolishError`-free `HistoryStoreException` with an actionable message. Tests: round trip,
  limit, missing file → empty, corrupt file → backup, unknown channel.
- `PromptOverrideStore`: override file in `directory/<relativePath>` wins over the bundled
  default; `reset` deletes it; `save` refuses a `polish.txt` without `{{CHANNEL_GUIDELINES}}`
  (clear error naming the placeholder) and treats blank text as reset. Tests with temp dirs.
- `RefineTest.kt` / `PromptAssemblerTest.kt` cover the new channel/refinement files.

## 3. Worker B — app data + composer session

- `DataStoreAppSettings`: implement the new flows (string set `disabled_channels`, boolean
  `learning_summary`, string `palette`). Tests in `DataStoreAppSettingsTest.kt`.
- `AppGraph`: `historyRepository` (new `app/data/HistoryRepository.kt`: `StateFlow<List<HistoryEntry>>`,
  `record`, `updateOutput(id, text)`, `delete`, `clear`, IO on `Dispatchers.IO`, mutex, file
  `filesDir/history.json`), `promptStore = PromptOverrideStore(filesDir/prompts, AssetPromptReader)`
  used by `PolishService`.
- `ComposerSession` (`app/ui/ComposerSession.kt`) collects the settings flows in `init`:
  - `ComposerState.enabledChannels`; if the selected channel is disabled, select the first enabled.
  - passes `learningSummary` to `polish`; `ComposerState.showLearningSummary` hides the section.
  - history: record each successful polish and make it current; refine success updates its output;
    new `ComposerEvent.SaveOutput` (sent by Composer before Copy/Replace) and starting a new
    request / `Open` / restore flush edited output; `ComposerEvent.RestoreHistory(id)` loads
    input, output, channel and result (ignored while working). Mirrors `AppModel+History.swift`.
  - Tests in `ComposerSessionTest.kt` with fakes in `app/src/test/.../ui/Fakes.kt`.

## 4. Worker C — app UI

- **Theme** (`app/ui/Theme.kt`): `PalettePreset { WRITING_DESK, LAGOON, SEPIA, SYSTEM }`; Lagoon and
  Sepia use the Mac hex values from `Sources/WritingAssistant/ThemePalette.swift` plus derived
  Android-only `border` / `inkWash` / `onInkWash`; `SYSTEM` uses `dynamicLight/DarkColorScheme`
  (minSdk 31, always available). `WritingAssistantTheme(preset)`. Unit test checks border vs paper
  ≥ 3:1 and onInkWash vs inkWash / onPrimary vs primary ≥ 4.5:1 for every static preset.
  `MainActivity` and `SheetHost` collect `settings.palette` and render after the first value, so a
  non-default palette doesn't flash.
- **Settings** (main app only; the sheet keeps just the key section): `SettingsScreen` stays as the
  "AI provider" section; new `PreferencesSection` + `PreferencesViewModel` below it:
  - "Writing for" modes: a switch per channel; the last enabled one can't be turned off.
  - "English learning summary" switch with one line on what it does.
  - "Appearance": radio list of the four palettes.
  - "Prompts" row → `PromptListScreen` (every `PromptFile.all`, "Edited" badge) →
    `PromptEditorScreen` (monospace multi-line field, Save, Restore default, error line) with
    `PromptEditorViewModel`.
- **History** (`app/ui/HistoryScreen.kt`): top-bar "History" action on the composer; list newest
  first (date, channel short name, first line of output); tap restores into the composer and goes
  back; per-row Delete; "Clear all" with an inline confirm step. Empty state text.
- **Composer**: chips from `state.enabledChannels`; refinement buttons include the two new ones
  (FlowRow already wraps); summary hidden when disabled; Copy/Replace send `SaveOutput` first.
- `MainActivity` navigation: `Screen { Composer, Settings, History, Prompts, PromptEditor }` with
  the edited file's path saved separately; Back returns one level.
- Strings in `res/values/strings_ui.xml`. UI tests in `ComposerUiTest.kt` plus new
  `HistoryScreenTest.kt` / `PreferencesTest.kt` (Robolectric).

## 5. Docs

`docs/architecture.md` (Android settings, prompt overrides, history file), README channel/
refinement lists, Mac channel list in `docs/next-steps.md` ("all six channels" → nine).

## Verification

- Android: `cd android && JAVA_HOME=$(/usr/libexec/java_home -v 21)
  ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ./gradlew :core:test :app:testDebugUnitTest lint ktlintCheck :app:assembleDebug`
  — zero warnings (warnings are errors).
- Mac: `swift build`, `scripts/test.sh`, `swift format lint -r Sources Tests`.
- Mutation spot checks: remove the forced-null summary in `PolishService`, the history limit, and
  the placeholder check in `PromptOverrideStore`; confirm a test fails each time.
- Emulator, debug build: turn a mode off → chip gone, restart → still off; summary off → no
  "What changed" and the request is faster; edit `channels/slack.txt`, polish, Restore default;
  try both new refinements; switch each palette in light and dark; polish twice, open History,
  restore, delete, clear; bottom sheet uses the chosen palette and enabled modes.
- Build release APK to `~/Downloads/` signed with the debug keystore for the phone; open a draft PR.
