# Native macOS rewrite of Writing Assistant (SwiftUI)

## Context

Today the "desktop app" is a compiled AppleScript that runs `cd <repo> && uv run python -m
assistant.desktop`, which boots FastAPI/uvicorn on :8765 and shows the vanilla-JS UI in a pywebview
window. It depends on the repo checkout, uv, a localhost port, and carries PWA leftovers (service
worker, manifest, heartbeat auto-shutdown). The goal is a real native macOS app written in
Swift/SwiftUI that keeps every current behaviour, drops the Python stack entirely, stores prompts in
`~/Library/Application Support/Writing Assistant/prompts/`, and adds an in-app prompt editor.

Environment facts: macOS 26.3, Swift 6.3.2, **Command Line Tools only (no Xcode)** — Swift Testing
(`import Testing`) and `swift format` are available. `claude` lives at `~/.local/bin/claude`.
Therefore: SwiftPM package + a shell script that assembles and ad-hoc signs the `.app`. No App
Sandbox (the app must spawn the `claude` CLI). Deployment target macOS 14 (for `@Observable`).

## Behaviour to preserve (port 1:1 from the Python code)

| Source | Behaviour |
|---|---|
| `assistant/models.py` | 6 channels (`slack`, `slack_informal`, `talking_points`, `formal`, `ai_prompt`, `other`); text 1–20 000 chars; response shape `polished_text`, `learning_summary{corrections[original,corrected,why], grammar_insight, vocabulary[term,meaning,example]}?`, `detected_language` (default "Unknown"), `was_translated` |
| `assistant/routing.py` | Haiku iff ≤60 words AND looks English (non-ASCII ratio ≤2 %, <2 Romance stopword hits after stripping `.,!?;:"'`); empty → Sonnet. Same model IDs and stopword list |
| `assistant/pipeline.py` | prompt = `polish.txt` with `{{CHANNEL_GUIDELINES}}` replaced by `channels/<channel>.txt` (both trimmed), read fresh on every request; **invariant: `was_translated` ⇒ summary nil**; missing `polished_text` / bad summary ⇒ format error |
| `assistant/claude_cli.py` | `claude --print --output-format text --model <m> --strict-mcp-config --mcp-config '{"mcpServers":{}}' --no-session-persistence`, prompt `"{system}\n\n---\n\n{text}"` on stdin; env strips `ANTHROPIC_API_KEY`, sets `MAX_THINKING_TOKENS=0`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`; 120 s timeout; one retry on non-zero exit only (never on timeout); JSON extraction: ```` ```json ```` fence → else first `{` … last `}` |
| `assistant/main.py` | Error messages: CLI not found (install link), "Claude took longer than 120 seconds. Please try again.", "Claude returned an error. Check the logs.", "Unexpected response format from Claude. Check the logs." Health check = claude resolvable |
| `static/*` | Textarea, channel radio group (default **Formal**), Process button + spinner, ⌘↩ submits, error banner, skeleton while loading, Polished Text card with language label ("Translated from X" highlighted) + Copy ("Copied" for 2 s), Learning Summary card (corrections before→after+why, grammar insight, vocabulary term — meaning + "example"), translated → skip message, empty summary → "Nothing to flag here — the text was already clean." Window 820×780, min 600×500 |

Dropped intentionally (web-only plumbing, no user-facing function): HTTP server/port, service
worker, manifest, heartbeat/`session.py`, `serve.sh`/`stop.sh`, AppleScript launcher.
Model name will be shown in the Polished Text header (README already claims this; JS never did).

## Target layout

```
Package.swift                         # swift-tools 6.0, platforms .macOS(.v14)
Sources/WritingAssistantCore/         # pure logic, no UI — fully unit-tested
  Channel.swift                       # enum Channel: String, CaseIterable + displayName
  PolishModels.swift                  # Codable PolishResult/LearningSummary/Correction/VocabularyItem
  ModelRouting.swift                  # pickModel(for:) — port of routing.py
  JSONExtraction.swift                # extractJSONObject(from:) — port of extract_json
  PromptStore.swift                   # seeding, read/write/restore, assemble(channel:)
  ClaudeCLI.swift                     # protocol ClaudeRunning + Process-based ClaudeCLI
  PolishService.swift                 # polish(text:channel:) async throws -> PolishResult
  PolishError.swift                   # LocalizedError cases with the messages above
  Resources/Prompts/                  # moved from assistant/prompts/ (git mv)
Sources/WritingAssistant/             # SwiftUI executable
  WritingAssistantApp.swift           # WindowGroup + Settings scene (⌘,) for prompt editor
  ComposerView.swift                  # input, channel picker (.radioGroup), Process (⌘↩)
  ResultsView.swift                   # PolishedCard, LearningSummaryCard, skeleton via .redacted
  PromptEditorView.swift              # sidebar of 7 files + monospaced TextEditor
  AppModel.swift                      # @Observable @MainActor state: input, channel, phase, error
Tests/WritingAssistantCoreTests/      # Swift Testing
Resources/AppIcon.icns, Info.plist    # icon moved from static/icons/icon.icns
scripts/build_app.sh                  # build, assemble, codesign -s -, install to ~/Applications
```

## Key design points

- **Claude binary resolution** (Finder-launched apps get a minimal PATH): check
  `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, then `/bin/zsh -lc 'command -v claude'`;
  cache the result. Child env PATH is prefixed with those dirs. Not found → banner at launch and on
  Process, with the same install message.
- **Process handling**: write prompt to stdin then close; drain stdout/stderr concurrently
  (avoid pipe-buffer deadlock); timeout via a Task that calls `terminate()` after 120 s →
  `PolishError.timeout`. Runs off the main actor; UI stays responsive.
- **`ClaudeRunning` protocol** is the only mock boundary — tests inject canned stdout/exit codes.
- **PromptStore** (`baseURL` injectable for tests): on launch copies any *missing* default from
  `Bundle.module` into Application Support (never overwrites user edits). `assemble` reads from
  disk every call, so edits from the app or any external editor apply on the next request.
  `restoreDefault(file)` overwrites one file from the bundle. Save validation: `polish.txt` must
  contain `{{CHANNEL_GUIDELINES}}`; no file may be empty.
- **Prompt editor** (Settings window, ⌘,): sidebar "Global rules" + 6 channels; editor shows
  unsaved-changes dot; buttons Save (⌘S), Revert, Restore Default (inline confirmation),
  Reveal in Finder. Validation errors shown inline, not saved.
- **Logging**: `os.Logger(subsystem: "local.writing-assistant")`; CLI stderr and format errors
  logged there. "Check the logs" messages and README point to
  `log stream --predicate 'subsystem == "local.writing-assistant"'` / Console.app.
- **Bundle resources**: build script copies SwiftPM's `WritingAssistant_WritingAssistantCore.bundle`
  into `Contents/Resources/`; verify `Bundle.module` resolves from the installed `.app` (milestone 3
  check). Fallback if not: copy prompts to `Contents/Resources/Prompts` and resolve via
  `Bundle.main` in the app, `Bundle.module` in tests.

## Execution model: orchestrator + parallel subagents

This session is the **orchestrator**. It owns the shared contract, launches workers, merges their
branches, and runs integration. Workers are `general-purpose` agents with `isolation: "worktree"`,
each on its own branch off `feat/NOJIRA-000_native_swift_app`, each owning a **disjoint set of files**, so merges
never conflict. Workers do not edit `Package.swift` or any `Contracts.swift` file; if they need a
contract change, they stop and report it, and the orchestrator decides.

```
Phase 0 (orchestrator, serial) ──► Phase 1 (6 workers in parallel) ──► Phase 2 (orchestrator)
 contracts + scaffold                W1 W2 W3 W4 W5 W6                    merge, wire, verify
                                                                          ──► Phase 3: review agent
                                                                          ──► Phase 4: Python removal
```

### Phase 0: Contract and scaffold (orchestrator, one commit)

Goal: make every worker able to compile and test against stable interfaces from minute one.

- **First action, before anything else:** create branch `feat/NOJIRA-000_native_swift_app` and copy this plan into
  the repo as `docs/native-macos-migration-plan.md`. `docs/` already exists in the repo, so the
  plan goes there rather than into a second folder. Commit it on its own as
  `Add native macOS migration plan`. Every worker prompt then refers to this file as the source of
  truth. Phase 4 keeps it, and only `docs/install.html` is deleted.
- Add `.build/` and `build/` to `.gitignore`.
- `Package.swift`: targets `WritingAssistantCore` (library, resources `.copy("Resources/Prompts")`),
  `WritingAssistant` (executable, depends on Core), and `WritingAssistantCoreTests`.
- `git mv assistant/prompts Sources/WritingAssistantCore/Resources/Prompts`.
- `Sources/WritingAssistantCore/Contracts.swift` holds the frozen public API. The concrete types
  have `fatalError("unimplemented")` bodies, and each worker replaces those bodies in their own file:
  - `enum Channel: String, CaseIterable, Sendable` with `displayName`
  - `struct PolishResult`, `LearningSummary`, `Correction`, `VocabularyItem` (Codable, Sendable,
    Equatable; `modelUsed` included)
  - `enum PolishError: LocalizedError, Equatable` with cases `claudeNotFound`, `timeout`,
    `cliFailed(stderr:)`, `badFormat(detail:)`, `emptyInput`, `inputTooLong` and their messages
  - `protocol ClaudeRunning: Sendable { func run(prompt: String, model: String, timeout: Duration) async throws -> String }`
  - `protocol PromptStoring: Sendable` with `seedMissingDefaults()`, `read(_:)`, `write(_:_:)`,
    `restoreDefault(_:)`, `assemble(for:)`, `fileURL(_:)`, `directoryURL`
  - `enum PromptFile: Hashable, CaseIterable { case global, channel(Channel) }`
  - `protocol Polishing: Sendable { func polish(text: String, channel: Channel) async throws -> PolishResult }`
- `Sources/WritingAssistant/Fakes.swift` (DEBUG only): `FakePolisher` and an in-memory `FakePromptStore`.
  UI workers use these, so they never depend on the Core implementations.
- Verify that `swift build` and `swift test` (empty suite) pass, then commit. From here on, workers branch.

### Phase 1: Parallel workers (launched in one message, run concurrently)

| Worker | Owns files (only these) | Deliverable | Tests it must add |
|---|---|---|---|
| **W1 Core logic** | `ModelRouting.swift`, `JSONExtraction.swift`, `PolishService.swift` (implements `Polishing` using injected `ClaudeRunning` + `PromptStoring`), `Tests/.../RoutingTests.swift`, `PipelineTests.swift` | Ports of `routing.py`, `extract_json`, `pipeline.polish`, plus input validation | All `test_routing.py` cases. From `test_pipeline.py`: the invariant (including a model that disobeys it), fenced, plain, preamble and garbage JSON, and missing `polished_text`. Plus input bounds (0, 1, 20 000 and 20 001 chars) |
| **W2 Claude CLI** | `ClaudeCLI.swift`, `ClaudeBinaryLocator.swift`, `Tests/.../ClaudeCLITests.swift` | `Process`-based `ClaudeRunning`: binary lookup, environment, flags, stdout and stderr drained at the same time, timeout, retry rule | Uses a temporary shell-script "claude" to test success, non-zero exit retried once then `cliFailed`, timeout not retried, `ANTHROPIC_API_KEY` stripped, and the not-found case |
| **W3 Prompt store** | `PromptStore.swift`, `Tests/.../PromptStoreTests.swift` | Implements `PromptStoring` with an injectable base URL, seeding from `Bundle.module`, and save validation | Seeding never overwrites, a deleted file gets re-seeded, restore, the placeholder check, the empty-file check, every channel assembles with no `{{`, and no em dash appears in the bundled channel files |
| **W4 Main window UI** | `WritingAssistantApp.swift`, `AppModel.swift`, `ComposerView.swift`, `ResultsView.swift` | The whole main window built against `Polishing`, with `PromptEditorView()` used as a placeholder reference | Unit tests for the `AppModel` states (idle, loading, success, error) using `FakePolisher`. Checked by building and running it with fakes |
| **W5 Prompt editor UI** | `PromptEditorView.swift`, `PromptEditorModel.swift` | The Settings-scene view built against `PromptStoring`: sidebar, editor, dirty-state indicator, Save (⌘S), Revert, Restore Default (inline confirmation), Reveal in Finder | Unit tests for `PromptEditorModel` (dirty tracking, validation error shown, restore) using `FakePromptStore` |
| **W6 Packaging + docs** | `scripts/build_app.sh`, `Resources/Info.plist`, `Resources/AppIcon.icns` (moved from `static/icons/icon.icns`), `Resources/icon-1024.png`, `README.md`, `docs/architecture.md`, `docs/next-steps.md` | The build/assemble/ad-hoc-sign/install script and a rewrite of the docs for the native app. Does **not** delete any Python files | `shellcheck` and `shfmt -d` both clean. The script runs against the Phase 0 scaffold and produces a `.app` that launches |

Each worker prompt includes the relevant rows of the "Behaviour to preserve" table, the
"Key design points" above, the list of files it owns, and the user's code-quality rules from
CLAUDE.md: functions of 100 lines or fewer, complexity of 8 or less, zero warnings, test behaviour
rather than implementation, and mock only the boundaries. Every worker must finish with
`swift build`, `swift test` and `swift format lint` passing on its branch, commit, and report
its branch name, files changed, test count, and any contract concerns.

### Phase 2: Integration (orchestrator)

1. Merge in dependency order: W3, then W2, then W1 (Core), then W5, then W4 (UI), then W6. Run
   `swift build` and `swift test` after each merge.
2. Delete the `fatalError` stubs from `Contracts.swift` so it keeps only the protocols and types.
   Wire the real `PromptStore`, `ClaudeCLI` and `PolishService` into `WritingAssistantApp`, and keep
   the fakes for tests only.
3. Run `scripts/build_app.sh`, then the live checks in Verification. Send any fix back to the worker
   that owns the file with SendMessage, so their context carries over; fix it here only if it's trivial.

### Phase 3: Review (one `feature-dev:code-reviewer` agent)

Review the full diff against `main`, covering correctness, behaviour parity with the Python code,
and the CLAUDE.md limits. The orchestrator triages the findings and routes fixes as in Phase 2.

### Phase 4: Remove the Python stack (orchestrator, final commit)

Delete `assistant/`, the Python `tests/`, `static/`, `pyproject.toml`, `uv.lock`, `docs/install.html`
and the `scripts/` files `serve.sh`, `stop.sh`, `launcher.applescript`, `build_launcher.sh` and
`make_icons.py`. Run `rg -i "uv run|uvicorn|pywebview|8765|heartbeat"` to catch leftovers, and update
the memory file `writing-assistant-project.md`. Open a PR from `feat/NOJIRA-000_native_swift_app`.

Agent count: 6 workers and 1 reviewer, which fits the "under 10 agents" guideline.

## Verification

- `swift build` and `swift test` — zero warnings, all tests green; `swift format lint -r Sources
  Tests` clean; `shellcheck scripts/build_app.sh && shfmt -d scripts/build_app.sh`.
- Mutation sanity: temporarily drop the `was_translated` invariant → invariant tests fail.
- `bash scripts/build_app.sh`, launch from Finder/Dock (proves PATH resolution works outside a
  terminal), then run the `docs/next-steps.md` live matrix: Spanish / Portuguese / English-with-
  errors / clean English across channels; copy button; ⌘↩; keyboard-only tab/arrow pass.
- Error paths: temporarily rename `~/.local/bin/claude` → launch banner; lower timeout to 1 s in a
  debug build → timeout banner.
- Prompt editor: edit `slack.txt` in-app, save, process → change reflected; remove the
  placeholder from Global rules → save blocked; Restore Default → bundled text back; edit the file
  in an external editor → next request uses it; delete a file in Application Support → relaunch
  re-seeds only that file.
