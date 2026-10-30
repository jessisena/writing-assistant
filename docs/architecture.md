# Architecture

## Problem

Writing in a second language across channels with different tone requirements (Slack, meeting talking
points, formal documents, AI prompts) means either shipping text that is grammatically fine but
tonally wrong, or hand-editing every message. Errors also get fixed invisibly — mistakes corrected
but never explained.

This tool closes both gaps: text goes in, a polished channel-appropriate version comes out, and when
the input was already in English, a short learning summary explains what changed and why.

---

## Key decisions

### One Claude call per request

Translation, style, and channel adaptation are interdependent judgments. Splitting them into
separate calls pays the input tokens repeatedly and multiplies CLI startup cost (~1–3s each). A
single call returning structured JSON is both cheaper and higher quality.

### `MAX_THINKING_TOKENS=0`

Extended thinking was measured turning an ~8s call into 75–99s. Disabling it is the single biggest
latency win.

### Local model routing heuristic — no triage call

A pure function (`ModelRouting.pickModel(for:)`) routes to Haiku for short, confidently-English
input and to Sonnet for everything else. A Haiku triage call would have been the obvious
"intelligent routing" design but adds a full round-trip to every request to save quota on some of
them. The local heuristic gets the same result for free.

### Haiku 4.5, not Haiku 5.5, for short English

Re-measured on 2026-10-29 through the CLI with the real polish prompt (5 short English Slack
messages × 3 runs, stream-json): Haiku 4.5 finished `polished_text` after a median 2.6 s (8.1 s
for the whole process), Haiku 5.5 after 10.0 s (14.8 s). Haiku 5.5 always uses adaptive thinking
(about 1,000–2,800 thinking tokens per request here): `MAX_THINKING_TOKENS=0`, `--effort low`
(7.8 s) and `alwaysThinkingEnabled: false` (11.1 s) don't turn it off, and the Claude Code docs
list no switch that does. Its learning summaries were better (it named Spanish/Portuguese
interference such as "assist" for "attend"), but its polished Slack text was wordier. Haiku is in
the routing for speed, so `ModelRouting.haikuModel` stays on Haiku 4.5. Re-check when Claude Code
offers a way to disable thinking for 5.x models.

### `learning_summary` gate — enforced in code

When input was not in English (`was_translated: true`), the learning summary is always nil. This is
enforced in **two** places: the prompt instructs it, and `PolishService` drops any summary that
comes back anyway. The prompt instruction alone is not a guarantee; the code is the actual
invariant. A non-nil `learningSummary` implies `wasTranslated == false`.

### CLI subprocess auth

Calls go through the `claude` CLI with subscription OAuth. `ANTHROPIC_API_KEY` is removed from the
child environment so the CLI never falls back to API billing.

### Native app, no server

The app is a SwiftUI process that calls the CLI directly. There is no local HTTP server, port or
web view. The request runs off the main actor, so the window stays responsive during the 10–30 s
call, and failures come back as typed `PolishError` values that the UI shows as a banner.

### Prompts as user-editable files

The prompts are plain text in `~/Library/Application Support/Writing Assistant/prompts/`, not
compiled into the binary. The app reads them on every request, so edits from the in-app editor or
any external editor apply to the next request. Bundled defaults are copied there when a file is
missing. When a bundled default changes, files the user hasn't edited are updated and edited files
are left alone, with a notice in Settings, so an upgrade never overwrites edits.

### Markdown between the app and Claude

The editors hold rich text (`NSAttributedString`). Requests send it to Claude as a small Markdown
subset (bold, italic, strikethrough, inline code, links, bullets, headings), and Claude returns
`polished_text` in the same subset, which is parsed back into rich text for the editable output.
Copy turns the edited output into HTML plus a plain-text fallback, so pasting into Slack keeps
the formatting. Emoji are plain Unicode and need no conversion. Model output is untrusted, so
parsing never throws: a line that fails to parse stays plain text, and HTML output is escaped.

### Service instead of in-place replacement

"Polish with Writing Assistant" in the Services menu sends the selection to the app and returns
nothing. Replacing the selection in place would block the calling app for the 8–20 s a request
takes, and services time out.

### No App Sandbox

The app has to spawn the `claude` binary from the user's home directory, which the sandbox does not
allow. It is signed ad hoc and installed locally; it is not distributed.

---

## Structure

```
Package.swift                        swift-tools 6.0, macOS 14
Sources/WritingAssistantCore/        library: all logic, no UI
  Contracts.swift                    Channel, Refinement, PolishResult + summary types,
                                     PolishError, PromptFile, and the ClaudeRunning /
                                     PromptStoring / Polishing protocols
  ModelRouting.swift                 pickModel(for:) + model ID constants
  JSONExtraction.swift               extract the JSON object from CLI output
  PromptStore.swift                  PromptStoring: seed, sync defaults, read, write, restore,
                                     assemble
  ClaudeBinaryLocator.swift          find the claude binary
  ClaudeCLI.swift                    ClaudeRunning backed by Process
  PolishService.swift                Polishing: validate, route, assemble, run, parse, invariant;
                                     polish and refine
  RichText.swift                     Markdown subset ↔ AttributedString, HTML and plain text
  TextDiff.swift                     word-level diff (DiffSegment: same / added / removed)
  LearningLog.swift                  format and append learning summaries to learning-log.md
  HistoryStore.swift                 HistoryEntry + history.json, newest 50, corrupt-file backup
  Resources/Prompts/                 bundled default prompts
    polish.txt                       4-step instructions + global rules
    channels/*.txt                   per-channel rules
    refinements/*.txt                shorter, more_casual, more_formal instructions
Sources/WritingAssistant/            SwiftUI executable
  WritingAssistantApp.swift          main window + Settings scene (⌘,), app delegate, menus
  AppModel.swift                     @Observable state: input, output, channel, loading,
                                     result, error, history; process, cancel, clear, copy
  AppModel+Refine.swift              quick refinements of the edited output
  AppModel+LearningLog.swift         append to and open the learning log
  AppModel+History.swift             record, save, restore and delete history entries
  RequestRunner.swift                the running request: its task, cancel, and a generation
                                     check so a stale answer can't overwrite a newer one
  RichTextEditor.swift               RichTextBridge (NSAttributedString ↔ AttributedString,
                                     paste normalization), FormattingTextView, RichTextEditor
  FormattingToolbar.swift            formatting buttons, emoji picker, Format menu
  ComposerView.swift                 input editor, channel picker, Process (⌘↩), Clear / Cancel
  ResultsView.swift                  Polished Text card (editor, Copy, diff toggle, Refine) and
                                     Learning Summary card
  DiffView.swift                     read-only diff of input against output
  HistoryView.swift                  History button (⌘Y) and popover
  ServiceProvider.swift              "Polish with Writing Assistant" service
  PromptEditorView.swift             prompt editor (Settings → Prompts)
  PromptEditorModel.swift            editor state: selection, dirty tracking, validation,
                                     newer-default notices
  ThemePalette.swift                 ThemeToken, ThemeColor, ThemePalette, the 3 presets,
                                     the `theme` environment value
  ThemeSettings.swift                @Observable preset + custom colours, saved in UserDefaults
  AppearanceSettingsView.swift       preset cards and colour pickers (Settings → Appearance)
  NSColor+Hex.swift                  0xRRGGBB ↔ sRGB NSColor
Tests/WritingAssistantCoreTests/     Swift Testing, Core logic
Tests/WritingAssistantTests/         Swift Testing, AppModel, PromptEditorModel, RichTextBridge,
                                     DiffView, ServiceProvider and theme settings
Resources/                           Info.plist (with NSServices), AppIcon.icns, icon-1024.png
scripts/build_app.sh                 build, assemble, sign, install
scripts/test.sh                      swift test with Command Line Tools framework paths
```

### Core library vs app

`WritingAssistantCore` holds everything that can be tested without a window. The app target owns
only state and views. Both talk to each other through the protocols in `Contracts.swift`.

### Protocols as test boundaries

- `ClaudeRunning` is the only boundary to the outside world. Core tests inject a runner that
  returns canned stdout or errors, so `PolishService` is tested without spawning the CLI.
  `ClaudeCLI` itself is tested against a temporary shell script standing in for `claude`.
- `PromptStoring` takes an injectable directory, so `PromptStore` tests use a temp folder.
- `Polishing` lets the UI tests drive `AppModel` with a fake polisher (`Fakes.swift`, DEBUG only).

### Prompt store

`PromptStore.standard()` points at `~/Library/Application Support/Writing Assistant/prompts/`.
On launch, `seedMissingDefaults()` copies any missing file from the bundled defaults.
`assemble(for:)` reads `polish.txt` and `channels/<channel>.txt` from disk, trims both, and
replaces `{{CHANNEL_GUIDELINES}}` with the channel file. `write` validates first: no file may be
empty, and `polish.txt` must contain the placeholder. `restoreDefault` overwrites one file from the
bundle. Refinements append `refinements/<name>.txt` to the assembled prompt as an extra
instruction.

`prompts/.defaults.json` maps each file's relative path to the SHA-256 of the bundled default it
was last seeded or restored from. `syncDefaults()` runs at launch after seeding:

- File unchanged from its recorded default, bundled default changed: overwritten, manifest
  updated.
- File edited, bundled default changed: left alone and returned as "newer default available".
  Settings shows a badge and a banner with Restore Default and Keep mine
  (`acknowledgeDefault(_:)`, which records the new hash without touching the file).
- No manifest entry: recorded if the file matches the bundled default, otherwise reported.

A corrupt manifest is logged, treated as missing and rewritten.

### Rich text

`RichText` (Core) converts between the Markdown subset and `AttributedString` with inline
presentation intents, and renders HTML and plain text. Only `[text](url)` and `<url>` make links:
bare URLs and email addresses stay plain text, since Foundation's parser would otherwise
autolink them. Emphasis markers are placed by code point, as the parser reads them, so emoji
inside bold or italic keep their style. `plainText(from:)` drops link targets, for
the diff and history previews; `clipboardText(from:)` writes them as `label (url)` for the plain
clipboard flavor. `RichTextBridge` (app) converts between
`AttributedString` and the `NSAttributedString` the editors use (font traits, strikethrough,
monospaced font, links), and normalizes pasted text: bold, italic, strikethrough, code and links
are kept; foreign fonts, sizes and colors are dropped, and the foreground is `NSColor.textColor`
so dark mode works. `FormattingTextView` is an `NSTextView` subclass with the toggle actions and a
`readSelection(from:type:)` override that normalizes rich text read by paste and drag-and-drop,
and reads plain text in the base style with `-`/`*` list markers turned into bullets. Its
`insertNewline(_:)` override continues a bullet list on Return and ends it on an empty bullet.
`RichTextEditor` wraps it for SwiftUI, and a `RichTextController` per
editor lets each `FormattingToolbar` act on its own editor. The Format menu sends to the first
responder.

### Theme

Views draw with six tokens (`ink`, `paper`, `desk`, `rule`, `redPencil`, `marginGreen`) read
from `@Environment(\.theme)`, a `ThemePalette`. Each token is a light and a dark `0xRRGGBB`
value, turned into a dynamic `NSColor` that follows the appearance of the view it is drawn in;
one `Color` is cached per value, so equal palettes give equal colours. `ThemeSettings` (owned by
the app, applied to both scenes with `.environment(\.theme, …)` and `.tint(palette.ink)`) holds a
`ThemePreset` plus per-token overrides; `palette` merges the two, and choosing a preset clears the
overrides. Every change is saved as a JSON string under the `theme` UserDefaults key
(`{"preset":"lagoon","overrides":{"ink":{"light":"#025F67","dark":"#6FCFC6"}}}`); a value that
doesn't parse is logged and loads as Writing Desk. System colours (error banner, prompt editor
notices) are not themed. `EnvironmentValues.theme` uses a plain `EnvironmentKey`, since `@Entry`
needs a macro plugin that ships only with Xcode.

### Diff, learning log and history

`TextDiff.words(from:to:)` tokenizes both sides' plain text into words and whitespace and uses
the standard library's `difference(from:)`. `DiffView` colors the segments and gives VoiceOver a
text version ("removed: …, added: …").

After a successful Process, `AppModel` appends the learning summary to `LearningLog` (skipped when
it is nil or empty; refinements never append) and records a `HistoryEntry` in `HistoryStore`. The
edited output is saved into the current entry on copy, refine, clear and before the next request,
not on every keystroke. A history file that doesn't decode is renamed to `history.corrupt.json`,
the store starts empty, and the app shows a banner. A file that can't be read, or a damaged one
that can't be moved aside, is left alone: the banner says so and `AppModel.savesHistory` stays
false until the next launch, so the first new entry never overwrites it.

### Service

`ServiceProvider` is `NSApp.servicesProvider`. It reads the pasteboard (RTF through
`RichTextBridge.normalized`, else plain text) and loads the text into the input with
`AppModel.loadInput(_:)`, which saves and leaves the current history entry and clears the old
result. It doesn't start a request: the user checks the channel and clicks Polish. If a request is
already running it shows a banner and keeps the input.
It then brings the main window forward. SwiftUI gives the `Window(id: "main")` NSWindow the
identifier `main`; when no such window exists (it was closed while Settings kept the app running),
the provider calls an `openWindow` action that the main window and Settings views hand to the app
delegate when they appear. The activation step is injected, so tests run without a window server.

### Data files

```
~/Library/Application Support/Writing Assistant/
  prompts/                 live prompts: polish.txt, channels/, refinements/, .defaults.json
  history.json             the newest 50 requests
  history.corrupt.json     a history file that couldn't be read, moved aside
  usage.json               token and cost totals per month
  usage.corrupt.json       a usage file that couldn't be read, moved aside
  learning-log.md          learning summaries, newest last
```

### CLI runner

`ClaudeBinaryLocator` checks `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`, then runs
`/bin/zsh -lc 'command -v claude'`, because apps launched from Finder get a minimal `PATH`. A
successful lookup is cached and looked up again if the cached path stops being executable, so
installing `claude` works without relaunching. Those directories are prefixed onto the child's
`PATH`. The child runs in the temporary directory, so it never picks up a project's context, and
`USER`/`HOME` are filled in if missing (the CLI needs `USER` to find its login).

`ClaudeCLI` runs:

```
claude --print --output-format stream-json --verbose --include-partial-messages \
  --model <model> --system-prompt-file <file> --tools "" --setting-sources "" \
  --disable-slash-commands --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
  --no-session-persistence
```

with only the user's text written to stdin, and environment `MAX_THINKING_TOKENS=0`,
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, `DISABLE_TELEMETRY=1`, `DISABLE_ERROR_REPORTING=1`,
no `ANTHROPIC_API_KEY`.

- `--system-prompt-file` replaces Claude Code's own system prompt with the assembled polish (or
  refinement) prompt. The file is written for each request into a new `WritingAssistant-<UUID>`
  directory in the temporary directory (directory 0700, file 0600), so the prompt never shows in
  `ps` or meets `ARG_MAX`, and the directory is deleted when the call returns, including after a
  failure, timeout or cancel. Both attempts of a retried call use the same file.
- `--tools ""` removes every built-in tool, so a draft can't trigger tool use, and
  `--disable-slash-commands` drops skills and commands.
- `--setting-sources ""` loads no user, project or local settings file, so the user's hooks,
  plugins and other settings don't run on polish calls. Settings such as `DISABLE_TELEMETRY` that
  usually live in `~/.claude/settings.json` are therefore set in the child environment instead.
  Managed (policy) settings and Claude Code's built-in plugins still load.
- `--bare` isn't used: it also skips the keychain, where the subscription login lives.
- An older `claude` that doesn't know one of these flags exits with "unknown option" (on stderr,
  or for some errors on stdout). That maps to `PolishError.cliOutdated`, which asks the user to
  run `claude update`, and is never retried.

stdout and stderr are drained at the same time to avoid a pipe-buffer deadlock. stdout is read as
one JSON event per line (`StreamJSONReader`): `text_delta` events go to the caller's `onText` as
they arrive, and the final `result` event gives the reply text, its `usage` (input, output,
cache write and cache read tokens) and `total_cost_usd`. After 120 s the process gets SIGTERM, then SIGKILL after a 2 s
grace. A non-zero exit is retried once, but only if no text was streamed yet; a timeout is never
retried. Cancelling the request or quitting the app terminates a running `claude` process.

The `result` event arrives about 2.5 s after the model's last token (CLI shutdown); the preview
makes up for it. Before 2026-10-30 each call also carried about 24K tokens of Claude Code's own
system prompt and tool definitions, cache-written at the 1-hour rate or read from the cache. With
the flags above, a Slack polish with the bundled prompts sends about 2K input tokens, none cached
(the prompt is below the cacheable minimum), and costs about a sixth as much.

Note (2026-10-30): the switch to these flags happened mid-month, so the October 2026 totals in
`usage.json` mix runs before and after it. Per-request comparisons need November data or a
measurement of single requests; `usage.json` was deliberately not reset.

### Progressive display, summary setting, token count and cost

`PolishService.polish` feeds the streamed text to `PolishedTextScanner`, which reports the
top-level `polished_text` the moment its JSON string closes (with `detected_language` and
`was_translated` if they came first). `AppModel` shows it as the result with no summary and a
placeholder summary card; the final result fills in the summary but keeps the output editor's
text, so edits made during the wait survive. A preview for a request that is no longer current is
ignored. After a cancel or failure the previewed text stays and is saved to history without a
summary.

Settings › General has "Show English learning summary" (UserDefaults `learningSummaryEnabled`).
When off, `PolishService` appends a note telling the model to skip Step 4 and drops any summary.

`PolishService` records the usage of every reply the CLI completes in `UsageStore` (`usage.json`,
totals per Gregorian "yyyy-MM" in the user's time zone), even when the reply then fails to parse.
Runs that end without a `result` event (cancelled, timed out, crashed) report no usage and aren't
counted, and neither is a failed first attempt that was retried, so the count is a slight
undercount. The toolbar and Settings › General show the current month, re-read after each request,
when the app becomes active and when Settings opens.

The cost is the CLI's own `total_cost_usd`, summed per month as `costUSD` next to the tokens; the
app keeps no price table. The CLI prices each run per model at API list prices (`"costBasis":
"list"`), including its 1-hour cache writes, which cost more than 5-minute ones and which the
token counts don't distinguish. The app runs on the user's subscription login, so the figure is
what the tokens would cost through the API, not what is billed; the UI says so. A `result` without
a numeric `total_cost_usd` still counts its tokens and adds nothing to the cost. The toolbar shows
cents ("48.2K tokens · $0.42 this month"); its tooltip and Settings show four decimals. A cost
above zero but under the smallest step shows as "<$0.01". `costUSD` is required in `usage.json`,
so a file written before it existed is treated as damaged and moved aside.

### Logging

`os.Logger` with subsystem `local.writing-assistant`. CLI stderr and unparsable responses are
logged there; the user-facing messages say "Check the logs".

### Packaging

`scripts/build_app.sh` runs `swift build -c release` and assembles `Writing Assistant.app`:

```
Contents/
  Info.plist                                   from Resources/Info.plist
  MacOS/WritingAssistant
  Resources/AppIcon.icns
  Resources/WritingAssistant_WritingAssistantCore.bundle/Prompts/...
```

With `--relaunch`, the script quits the running app (by bundle id, through `osascript`) after
signing and before replacing the install, and runs `open` on the new install at the end. After
installing, the script runs `/System/Library/CoreServices/pbs -update` so the service shows
up in the Services menu without logging out.

The SwiftPM resource bundle goes in `Contents/Resources` because `codesign` rejects extra files at
the `.app` root. The generated `Bundle.module` accessor only looks at the `.app` root and at the
absolute `.build` path, so `PromptStore.bundledDefaultsURL` looks up the bundle through
`Bundle.main` first and falls back to `Bundle.module` for `swift run` and tests. The app is
then signed ad hoc (`codesign --sign -`) and copied to `~/Applications`.

---

## Request flow

```
paste + channel, Process (⌘↩)
      │
      ▼  AppModel → PolishService.polish(text:channel:)
┌────────────────────────────────────────┐
│ validate: 1–20,000 characters          │
│ pickModel(for: text)  ← pure function  │
│   ≤60 words + confident English → Haiku│
│   everything else             → Sonnet │
│ PromptStore.assemble(for: channel)     │
└────────────────────────────────────────┘
      │
      ▼  one ClaudeCLI.run() call, stream-json
         MAX_THINKING_TOKENS=0, MCP disabled
         polished_text closes → onPreview (shown at once)
┌────────────────────────────────────────┐
│ polish.txt  (4 steps)                  │
│  1. detect language                    │
│       not English → translate          │
│       English     → skip               │
│  2. apply global style guidelines      │
│  3. apply {{CHANNEL_GUIDELINES}}       │
│  4. emit JSON                          │
└────────────────────────────────────────┘
      │  JSON extraction (```json fence, else first { … last })
      │  was_translated ⇒ learning summary dropped
      ▼
PolishResult{polishedText, learningSummary?,
             detectedLanguage, wasTranslated, modelUsed}
```

---

## Error mapping

| Failure | `PolishError` | Message |
|---|---|---|
| Empty input | `emptyInput` | Please paste some text before processing. |
| Over 20,000 characters | `inputTooLong` | Text is too long. The limit is 20,000 characters. |
| `claude` binary not found | `claudeNotFound` | claude CLI not found, with the install link |
| No response within 120 s | `timeout` | Claude took longer than 120 seconds. Please try again. |
| CLI exits non-zero twice | `cliFailed` | Claude returned an error. Check the logs. |
| Unparsable JSON / missing `polished_text` | `badFormat` | Unexpected response format from Claude. Check the logs. |
| Prompt files unreadable | `promptUnavailable` | Couldn't read the prompt files, with a pointer to Settings |

The app also checks for `claude` at launch (`checkReady()`) and shows the not-found banner before
the first request.

---

## Model IDs

Defined as constants in `Sources/WritingAssistantCore/ModelRouting.swift`:

- `haikuModel = "claude-haiku-4-5-20251001"`
- `sonnetModel = "claude-sonnet-5-5"`

The Android app has the same values as `Provider.ANTHROPIC.models` in
`android/core/src/main/kotlin/local/writingassistant/core/Contracts.kt`. Update both files
together when newer models are available. Groq's models live next to them in `Provider.GROQ`
(see [Providers](#providers)).

---

## Android

`android/` is a Gradle project (Kotlin DSL, version catalog in `gradle/libs.versions.toml`) with
two modules. It ports the Core logic to Kotlin and replaces the `claude` CLI with one HTTPS call
to an LLM provider, authenticated with the user's own API key: the Anthropic Messages API by
default, or Groq's OpenAI-compatible API. The CLI runs on subscription OAuth as a local
subprocess, which Android can't do.

### Change logic in both apps

The model routing heuristic, JSON extraction, the polish and refine pipeline and the
`learning_summary` invariant (always null when `was_translated` is truthy) exist twice: in Swift
under `Sources/WritingAssistantCore/` and in Kotlin under `android/core/`. The Kotlin tests are
ports of the Swift tests. A change to any of these, or to the Anthropic model IDs, has to be made
in both languages together with its tests in both. Each Kotlin file names the Swift file it
mirrors in its doc comment.

Routing differs in one way: Swift's `ModelRouting.pickModel(for:)` returns a Claude model ID,
while Kotlin's `ModelRouting.pickTier(text)` returns a `ModelTier` (`SMALL` or `LARGE`) that each
provider maps to its own model. The heuristic is the same, and a change to it still goes in both.

Prompts are not duplicated (see below), so prompt edits need no Android change.

### Modules

```
android/
  settings.gradle.kts                  :core and :app
  gradle/libs.versions.toml            every dependency and plugin version
  lint.xml                             shared Android lint config
  core/                                pure Kotlin/JVM, no Android dependencies
    src/main/kotlin/local/writingassistant/core/
      Contracts.kt                     Channel, Refinement, PolishResult, LearningSummary,
                                       PolishError, PromptFile, Provider, Models, ModelTier,
                                       Backend, and the LlmClient / PromptReading /
                                       Polishing interfaces
      ModelRouting.kt                  pickTier(text) → ModelTier
      JsonExtraction.kt                extract the JSON object from model output
      PromptAssembler.kt               polish.txt + channel file; DirectoryPromptReader
      PolishService.kt                 Polishing: validate, route, assemble, call, parse,
                                       invariant; polish (optionally without the learning
                                       summary) and refine
      PromptOverrideStore.kt           user-edited prompt copies over the bundled defaults
      HistoryStore.kt                  HistoryEntry + history.json, newest 50, corrupt backup
      api/HttpTransport.kt             shared OkHttp call with cancellation, timeout, key
                                       redaction, JSON config, isWellFormedKey
      api/AnthropicClient.kt           LlmClient backed by POST /v1/messages
      api/GroqClient.kt                LlmClient backed by POST /openai/v1/chat/completions
    src/test/                          JUnit ports of the Swift Core tests, MockWebServer
                                       tests for both clients
    src/testFixtures/                  FakeLlmClient, shared with :app tests
    src/liveTest/                      LivePolishTest against the real APIs
  app/                                 Android app, Jetpack Compose, minSdk 31
    src/main/AndroidManifest.xml       MainActivity, ProcessTextActivity, ShareActivity
    src/main/kotlin/local/writingassistant/app/
      WritingAssistantApp.kt           Application, owns the AppGraph
      AppGraph.kt                      wires PolishService, both clients, key store, settings,
                                       prompt store and history
      MainActivity.kt                  composer, History, Settings, Prompts and the prompt editor,
                                       Back goes up one level
      data/ApiKeyStore.kt              interface; KeystoreApiKeyStore implements it
      data/KeystoreApiKeyStore.kt      AES-GCM with an Android Keystore key, in DataStore
      data/AppSettings.kt              interface; DataStoreAppSettings implements it
      data/DataStoreAppSettings.kt     last-used channel, provider, disabled channels, learning
                                       summary switch and palette, in Preferences DataStore
      data/HistoryRepository.kt        in-memory history shared by composer and History screen,
                                       saved to filesDir/history.json
      data/AssetPromptReader.kt        PromptReading from the bundled assets
      intents/                         ProcessTextActivity, ShareActivity, SheetHost (the
                                       bottom sheet both activities show)
      ui/Composer.kt                   input, channel chips, Polish/Cancel, result, refinements,
                                       learning summary, Copy and Replace
      ui/ComposerSession.kt            composer state and the one in-flight request, app-scoped
      ui/ComposerViewModel.kt          thin wrapper exposing the session to a screen
      ui/SettingsScreen.kt             provider picker, API key entry with Save, Test and Clear
      ui/SettingsViewModel.kt          reads and writes the provider and its key, runs the test
      ui/PreferencesSection.kt         Writing for switches, learning summary, palette, Prompts
      ui/PreferencesViewModel.kt       reads and writes those settings
      ui/PromptsScreen.kt              prompt list with Edited labels, and the prompt editor
      ui/PromptEditorViewModel.kt      loads, saves and restores one prompt off the main thread
      ui/HistoryScreen.kt              history list with restore, delete and clear all
      ui/Markdown.kt, InlineParser.kt  Markdown subset → AnnotatedString, HTML and plain text
      ui/Clipboard.kt                  ClipData.newHtmlText with a plain-text fallback
      ui/Theme.kt                      Material 3 colour schemes for each PalettePreset (Writing
                                       Desk, Lagoon, Sepia, System dynamic colour)
    src/test/                          Robolectric and JVM tests: key store, settings, asset
                                       prompts, view models, Markdown, composer, settings,
                                       prompts and history UI, navigation, theme contrast
```

`:core` holds everything that runs without Android, including the API client, so the pipeline
and the client are tested on the plain JVM. `:app` depends on `:core` and owns state, views,
storage and the system integration. `AppGraph` is the only place the real implementations are
built; tests construct view models with fakes instead.

### Shared prompts

`app/build.gradle.kts` adds `Sources/WritingAssistantCore/Resources/Prompts/` as an assets
directory, so the APK bundles the same `polish.txt`, `channels/*.txt` and `refinements/*.txt` as
the Mac app, and a change to those bundled defaults reaches both apps with their next build.
Edits made in the Mac app's Settings live in its Application Support folder and don't reach
Android. On Android, `PromptOverrideStore` (`:core`) reads `filesDir/prompts/<relativePath>` when
the user edited that file in Settings → Prompts, and otherwise the bundled default through
`AssetPromptReader`. Saving the default text deletes the edit, and saving follows the same rules
as the Mac (`PromptValidationException`: not empty, global rules keep the placeholder).
Files are read on each request, so an edit applies to the next one. `:core` tests and `liveTest` read
the same directory through `DirectoryPromptReader`, passed in as the `prompts.dir` system
property.

Every provider gets the same prompts, so they must keep producing a single valid JSON object on
each of them. Groq's JSON mode also rejects a prompt that doesn't contain the word "JSON";
`polish.txt` contains it, and refine prompts include `polish.txt`.

### Providers

`Provider` (`Contracts.kt`) lists the services the user can pick: `ANTHROPIC` and `GROQ`. Each has
a stable `id` (used in storage keys), a `displayName`, a `keyUrl` for the Settings link, and a
`Models(small, large)` pair:

| Provider | `small` | `large` |
|---|---|---|
| Anthropic | `claude-haiku-4-5-20251001` | `claude-sonnet-5-5` |
| Groq | `openai/gpt-oss-20b` | `openai/gpt-oss-120b` |

`PolishService` takes a `suspend () -> Backend`, where `Backend` is an `LlmClient` plus its
`Models`. `polish`, `refine` and `checkReady` resolve the backend once per call, so a provider
change in Settings applies to the next request, and pick
`models.forTier(ModelRouting.pickTier(input))`. `modelUsed` reports that model ID. A secondary
constructor, `PolishService(client, prompts)`, always uses Anthropic's models; tests use it.

`AnthropicClient` and `GroqClient` share `api/HttpTransport.kt`: the OkHttp call wrapper with
the per-call timeout and cancellation, timeout and network error mapping, the key `Redactor`,
the JSON configuration, and `isWellFormedKey`.

### API clients

`AnthropicClient` sends the assembled prompt and the input, joined as in the Swift app, as one
user message, with `x-api-key`, `anthropic-version: 2023-06-01` and `max_tokens` 16000. Thinking
stays off, as on the Mac: Sonnet 5.5 requests send `thinking: {"type": "between_tools"}`
(Sonnet 5.5 thinks adaptively when the field is left out and rejects `disabled`), and Haiku 4.5
requests send no thinking field, since Haiku doesn't think unless asked.

Each call, on either client, has a 120 s timeout and is not retried. Cancelling the calling
coroutine cancels the HTTP call. Each client
reads its provider's key from the key store on every call and redacts it from every error
message. Anthropic responses map to `PolishError`:

| Response | `PolishError` |
|---|---|
| No stored key | `MissingApiKey` |
| Key with a character outside `!`..`~` (checked before sending, and on Save/Test) | `MalformedApiKey`: "The API key contains characters that aren't allowed. Paste it again." |
| Keystore, cipher or DataStore failure in the key store | `KeyStorageFailed`: "Couldn't access the secure key storage on this device. Try again, or clear and re-enter the key." |
| 401, 403 | `InvalidApiKey` |
| 402, or 400 mentioning "credit balance" | `NoCredits` |
| 429, 503, 529 | `Overloaded` |
| Other non-2xx | `ApiFailed` (status and the API's message) |
| Timeout | `Timeout` |
| Other network failure | `Network` |
| `stop_reason` `max_tokens` | `OutputTooLong`: "The reply was cut off because the text is too long. Try a shorter selection." |
| `stop_reason` `refusal` | `Refused`: "The AI service declined to process this text. Try rewording it." |
| No text content block, or unparsable body | `BadFormat` |
| Any other exception in the composer or Settings | `Unexpected`: "Something went wrong (exception class). Please try again." |

`checkAvailable()`, used by the Settings Test button, sends "Hi" to Haiku with `max_tokens` 1.

`GroqClient` sends the same single user message to `POST /openai/v1/chat/completions` with
`Authorization: Bearer <key>` and:

- `response_format: {"type": "json_object"}` on every polish and refine call (JSON mode).
- `reasoning_effort: "low"` and `include_reasoning: false`, because gpt-oss always reasons: `low`
  is the lowest effort Groq allows, and the reasoning stays out of the reply.
- `max_completion_tokens` 2,048. The free tier allows 8K tokens per minute and counts this cap
  against that budget before the reply starts, so a 16K cap like Anthropic's would fail every
  request with 413. 2,048 leaves room for a polish and a refine in the same minute.

Groq responses map to `PolishError` (key, timeout and network errors as for Anthropic):

| Response | `PolishError` |
|---|---|
| 401, 403 | `InvalidApiKey` |
| 413 (the request is over the provider's token limits) | `TooLongForProvider` |
| 429 (includes going over a tokens-per-minute limit), 503 | `Overloaded` |
| 400 with error code `json_validate_failed` | `BadFormat` |
| Other non-2xx | `ApiFailed` (status and the API's message) |
| `finish_reason` `length` | `OutputTooLong` |
| No `choices`, no message content, or unparsable body | `BadFormat` |

Groq has no credit or refusal case, so `NoCredits` and `Refused` only come from Anthropic.
`checkAvailable()` sends "Hi" to the small model with `max_completion_tokens` 1 and no JSON mode.

### API key and settings

`ApiKeyStore` is keyed by provider (`read`, `write` and `clear` take a `Provider`).
`KeystoreApiKeyStore` encrypts each key with one AES-256-GCM key held in the Android Keystore and
stores the IV and ciphertext, Base64-encoded, in a `secrets` Preferences DataStore under
`<provider id>_api_key`, so the Anthropic key keeps the `anthropic_api_key` name it had before
Groq was added. A value that
can't be decrypted (for example after the Keystore key was invalidated) is cleared and read as no
key. `allowBackup` is off and the data extraction rules exclude everything, since the ciphertext
is useless without the device's Keystore key.

Debug builds get `BuildConfig.DEBUG_API_KEY` from `ANTHROPIC_API_KEY` and
`BuildConfig.DEBUG_GROQ_API_KEY` from `GROQ_API_KEY` in `android/local.properties`.
`SettingsViewModel` uses them only to prefill the field when the selected provider has nothing
stored; a key is stored once the user saves or tests it. Release builds set both to an empty
string.

`DataStoreAppSettings` keeps the last-used channel, which the composer preselects, and the
selected provider (Anthropic until the user picks another). `AppGraph` builds both clients once
and gives `PolishService` a backend lambda that reads `settings.provider()` on every request. The
Settings screen's Anthropic | Groq segmented buttons save the choice right away and load that
provider's key; Save, Test and Clear act on the selected provider.

### Composer

`ComposerSession` holds the composer state and runs one request at a time in an app-wide
coroutine scope owned by `AppGraph`, so the full-screen app and the sheets share one composer.
`ComposerViewModel` only exposes the session to a screen. Closing a sheet mid-request doesn't
cancel the request: opening the app (or selecting the same text again) shows the result. Cancel
cancels the job, and a generation number keeps a cancelled or replaced request from overwriting
newer state, as `RequestRunner.swift` does. Opening a sheet with different text cancels any
request and starts over, so Replace never returns a result for other text. A failed request can
be retried from the error banner. Polish is disabled while the key store holds no key for the
selected provider, and `MainActivity` opens Settings once in that case.

### System integration

- `ProcessTextActivity` handles `ACTION_PROCESS_TEXT`, which adds **Polish** to the
  text-selection menu of other apps. It is a translucent activity that hosts the composer in a
  bottom sheet, prefilled with the selection. **Replace** returns the polished text as
  `EXTRA_PROCESS_TEXT`, and is hidden when the caller sets `EXTRA_PROCESS_TEXT_READONLY`.
- `ShareActivity` handles `ACTION_SEND` with `text/plain` and opens the same sheet with Copy only.
- Copy and Replace close the sheet, as do swiping it down, back and tapping outside it. With no
  key stored, the sheet shows Settings first and returns to the composer once a key is saved.

Unlike the macOS service, PROCESS_TEXT can return replacement text, because the calling app isn't
blocked while the sheet is open.

### Build and checks

Kotlin compiles with warnings as errors, and Android lint runs with `warningsAsErrors` on both
modules. ktlint runs on every module. The CI `android` job in `.github/workflows/ci.yml` runs
`./gradlew :core:test :app:testDebugUnitTest lint ktlintCheck :app:assembleDebug` on JDK 21.
`:core:liveTest` is a separate test source set that calls the real APIs. Each provider's cases
run only when its key (`ANTHROPIC_API_KEY`, `GROQ_API_KEY`) is set in the environment or
`local.properties`, and the task is skipped when neither is, so CI never needs a key.
