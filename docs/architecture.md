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
  PromptEditorView.swift             prompt editor (Settings window)
  PromptEditorModel.swift            editor state: selection, dirty tracking, validation,
                                     newer-default notices
Tests/WritingAssistantCoreTests/     Swift Testing, Core logic
Tests/WritingAssistantTests/         Swift Testing, AppModel, PromptEditorModel, RichTextBridge,
                                     DiffView and ServiceProvider
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
presentation intents, and renders HTML and plain text. `plainText(from:)` drops link targets, for
the diff and history previews; `clipboardText(from:)` writes them as `label (url)` for the plain
clipboard flavor. `RichTextBridge` (app) converts between
`AttributedString` and the `NSAttributedString` the editors use (font traits, strikethrough,
monospaced font, links), and normalizes pasted text: bold, italic, strikethrough, code and links
are kept; foreign fonts, sizes and colors are dropped, and the foreground is `NSColor.textColor`
so dark mode works. `FormattingTextView` is an `NSTextView` subclass with the toggle actions and a
`readSelection(from:type:)` override that normalizes rich text read by paste and drag-and-drop.
`RichTextEditor` wraps it for SwiftUI, and a `RichTextController` per
editor lets each `FormattingToolbar` act on its own editor. The Format menu sends to the first
responder.

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
`RichTextBridge.normalized`, else plain text), loads the text into the input and starts a request
with the current channel. If a request is already running it shows a banner and keeps the input.
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
claude --print --output-format text --model <model> \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' --no-session-persistence
```

with `"{system}\n\n---\n\n{text}"` written to stdin, and environment
`MAX_THINKING_TOKENS=0`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, no `ANTHROPIC_API_KEY`.
stdout and stderr are drained at the same time to avoid a pipe-buffer deadlock. After 120 s the
process gets SIGTERM, then SIGKILL after a 2 s grace. A non-zero exit is retried once; a timeout is
never retried. Cancelling the request or quitting the app terminates a running `claude` process.

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

After installing, the script runs `/System/Library/CoreServices/pbs -update` so the service shows
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
      ▼  one ClaudeCLI.run() call
         MAX_THINKING_TOKENS=0, MCP disabled
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

Update these constants when newer models are available to the CLI.
