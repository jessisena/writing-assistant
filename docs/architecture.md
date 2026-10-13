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
any external editor apply to the next request. Bundled defaults are copied there only when a file
is missing, so an upgrade never overwrites edits.

### No App Sandbox

The app has to spawn the `claude` binary from the user's home directory, which the sandbox does not
allow. It is signed ad hoc and installed locally; it is not distributed.

---

## Structure

```
Package.swift                        swift-tools 6.0, macOS 14
Sources/WritingAssistantCore/        library: all logic, no UI
  Contracts.swift                    Channel, PolishResult + summary types, PolishError,
                                     PromptFile, and the ClaudeRunning / PromptStoring /
                                     Polishing protocols
  ModelRouting.swift                 pickModel(for:) + model ID constants
  JSONExtraction.swift               extract the JSON object from CLI output
  PromptStore.swift                  PromptStoring: seed, read, write, restore, assemble
  ClaudeBinaryLocator.swift          find the claude binary
  ClaudeCLI.swift                    ClaudeRunning backed by Process
  PolishService.swift                Polishing: validate, route, assemble, run, parse, invariant
  Resources/Prompts/                 bundled default prompts
    polish.txt                       4-step instructions + global rules
    channels/*.txt                   per-channel rules
Sources/WritingAssistant/            SwiftUI executable
  WritingAssistantApp.swift          main window + Settings scene (⌘,)
  AppModel.swift                     @Observable state: input, channel, phase, error
  ComposerView.swift                 text input, channel picker, Process (⌘↩)
  ResultsView.swift                  Polished Text and Learning Summary cards
  PromptEditorView.swift             prompt editor (Settings window)
  PromptEditorModel.swift            editor state: selection, dirty tracking, validation
Tests/WritingAssistantCoreTests/     Swift Testing, Core logic
Tests/WritingAssistantTests/         Swift Testing, AppModel and PromptEditorModel
Resources/                           Info.plist, AppIcon.icns, icon-1024.png
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
bundle.

### CLI runner

`ClaudeBinaryLocator` checks `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`, then runs
`/bin/zsh -lc 'command -v claude'`, because apps launched from Finder get a minimal `PATH`. The
result is cached, and those directories are prefixed onto the child's `PATH`.

`ClaudeCLI` runs:

```
claude --print --output-format text --model <model> \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' --no-session-persistence
```

with `"{system}\n\n---\n\n{text}"` written to stdin, and environment
`MAX_THINKING_TOKENS=0`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, no `ANTHROPIC_API_KEY`.
stdout and stderr are drained at the same time to avoid a pipe-buffer deadlock. A task terminates
the process after 120 s. A non-zero exit is retried once; a timeout is never retried.

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
- `sonnetModel = "claude-sonnet-4-6"`

Update `sonnetModel` here when a newer Sonnet becomes available to the CLI.
