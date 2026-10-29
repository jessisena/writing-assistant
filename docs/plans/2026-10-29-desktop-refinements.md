# Desktop refinements: on-click polish, Haiku 5.5, summary toggle, progressive display, tokens, refine tones

## Context

Six improvements to the macOS app (SwiftPM, `Sources/WritingAssistantCore` + `Sources/WritingAssistant`):

1. The Services shortcut ("Polish with Writing Assistant") currently loads the selection **and starts
   polishing** (`ServiceProvider.handle` → `model.startProcessing()`). It should only load the text;
   the user clicks Polish.
2. Haiku 5.5 was rejected on 2026-10-27 as ~2x slower via the CLI. Re-measure; switch if close.
3. A setting to turn off the English learning summary.
4. Show the polished text as soon as it exists, before the learning summary is done.
5. Track tokens spent this month.
6. Two new refinements: "More diplomatic" and "More assertive".

User decisions: tokens shown in the main window toolbar **and** a new Settings › General tab;
progressive display via **one streamed CLI call** (`stream-json`); Haiku 5.5 **benchmark, switch if
time-to-polished-text is within ~25% and quality is equal or better**.

Branch: `feat/NOJIRA-000_desktop_refinements` (branch hook needs that shape). Save this plan as
`docs/plans/2026-10-29-desktop-refinements.md`.

## Step 0 — spike + benchmark (main session, before the contract)

- One tiny real call: `claude --print --output-format stream-json --verbose
  --include-partial-messages --model claude-haiku-4-5-20251001` with the existing headless flags.
  Record the exact event shapes: `stream_event` → `content_block_delta`/`text_delta`, the final
  `{"type":"result", "result", "is_error", "usage": {input_tokens, output_tokens,
  cache_creation_input_tokens, cache_read_input_tokens}}`, and whether thinking blocks appear.
  Save a captured transcript as a test fixture (`Tests/WritingAssistantCoreTests/Fixtures/`).
- Haiku benchmark (scratchpad script, not committed): 5 short English samples × 3 runs × {Haiku 4.5,
  Haiku 5.5}, same env/flags as `ClaudeCLI.makeEnvironment`. Measure time to the delta that closes
  `polished_text`, total time, output tokens, and whether 5.5 emits thinking despite
  `MAX_THINKING_TOKENS=0` (likely cause of the earlier 2x; if so, retry with `--effort low` /
  `--settings '{"alwaysThinkingEnabled":false}'`). Compare outputs side by side for quality.
- If the rule passes: `ModelRouting.haikuModel = "claude-haiku-5-5"` (+ any flag that fixed speed,
  in `ClaudeCLI.headlessFlags`), update `RoutingTests`, `docs/architecture.md`. Either way, record
  the numbers in `docs/architecture.md` and update the memory file's "Model constants" note.

## Contract commit (main session)

`Sources/WritingAssistantCore/Contracts.swift`:

- `Refinement` gains `.moreDiplomatic = "more_diplomatic"`, `.moreAssertive = "more_assertive"`
  ("More diplomatic", "More assertive"), plus bundled prompt files
  `Resources/Prompts/refinements/more_diplomatic.txt` / `more_assertive.txt` in the style of the
  existing three (keep meaning, no new facts, no em dashes, keep emoji/Markdown). Diplomatic: soften
  demands into suggestions, acknowledge the reader, collaborative wording, without diluting the
  substance. Assertive: lead with the ask/decision, drop hedges ("just", "I think", "maybe") and
  needless apologies, stay respectful. `seedMissingDefaults` already seeds new files; the prompt
  editor lists `PromptFile.allCases` automatically.
- `TokenUsage: Codable, Sendable, Equatable` — `input`, `output`, `cacheCreation`, `cacheRead`,
  `total`, `+`.
- `ClaudeReply { text: String; usage: TokenUsage? }`.
- `ClaudeRunning.run(prompt:model:timeout:onText: @Sendable (String) -> Void) async
  throws(PolishError) -> ClaudeReply` (`onText` receives text deltas in order).
- `PolishPreview { polishedText: String; detectedLanguage: String?; wasTranslated: Bool? }`.
- `Polishing.polish(text:channel:includeLearningSummary:onPreview: @Sendable (PolishPreview) ->
  Void)`; `refine` unchanged in shape.
- `UsageRecording: Sendable { func record(_ usage: TokenUsage) throws }` (PolishService records
  every reply it gets, including ones that then fail to parse, since the tokens were spent).
- Update `Fakes.swift` (`FakePolisher`, `GatedPolisher` gain preview emission/gating) and the test
  runners in `PipelineTests`/`RefinementTests` so everything compiles; stub bodies may `fatalError`
  only where a worker owns the implementation.

## Wave 1 — three parallel worktree workers (branch from the contract commit)

### W1 Core streaming (`ClaudeCLI.swift`, new `PolishedTextScanner.swift`, `PolishService.swift`)

- `ClaudeCLI`: arguments become `--print --output-format stream-json --verbose
  --include-partial-messages`. `OutputCollector` for stdout gets an optional line handler that
  splits on `\n` across chunks; each line is decoded with `JSONSerialization`; text deltas go to
  `onText`; the `result` event supplies the final text and `usage`; `is_error: true` →
  `.cliFailed`; unknown events ignored; no `result` event → `.badFormat`-style failure. Retry the
  non-zero exit only when no delta was emitted yet (otherwise a retry would replay the preview).
  "Not logged in" stdout fallback keeps working (non-JSON lines collected for `failureDetail`).
- `PolishedTextScanner` (incremental, pure): fed deltas; starts at the first `{`; tracks depth and
  string/escape state; captures top-level `detected_language` / `was_translated` and, once the
  top-level `polished_text` string closes, decodes it (JSON escapes incl. `\uXXXX` surrogates) and
  reports it once. Tests: hand cases (fences, preamble, escapes, field order, nested
  `"polished_text"` keys inside `learning_summary` ignored) plus a property test: random objects
  serialized by `JSONSerialization`, split into random chunks, yield exactly the decoded
  `polished_text` (existing pattern: `RichTextPropertyTests.swift`).
- `PolishService.polish`: feeds `onText` into a scanner and calls `onPreview` once; the final parse
  still uses `reply.text` via `JSONExtraction` (unchanged invariants). When
  `includeLearningSummary` is false, append a fixed note after the assembled prompt (like
  `refinementNote`): "The learning summary is turned off: skip Step 4 and set learning_summary to
  null." and force `learningSummary = nil` regardless of the reply. Records `reply.usage` through an
  injected optional `UsageRecording` for polish and refine; a record failure is logged, never fails
  the request.

### W2 Usage store (new `Sources/WritingAssistantCore/UsageStore.swift`)

- `UsageStore: UsageRecording`, `final class … Sendable` with an `OSAllocatedUnfairLock`, file
  `~/Library/Application Support/Writing Assistant/usage.json` (`.standard()`, mirroring
  `HistoryStore.standard()`), shape `{"months": {"2026-10": {input, output, cacheCreation,
  cacheRead, requests}}}`, atomic writes. Month key from an injected `now: () -> Date` and
  `Calendar` (user's time zone). `currentMonth() -> MonthlyUsage`. Damaged file → moved aside like
  `HistoryStoreError.corrupted`, counting restarts. Tests with temp dirs: accumulation, month
  rollover, missing file, corrupt file, concurrent records.

### W3 App (`AppModel*.swift`, `ResultsView.swift`, `ServiceProvider.swift`, `WritingAssistantApp.swift`, new `GeneralSettingsView.swift`)

- **Shortcut**: new `AppModel.loadInput(_:)` — saves/leaves the current history entry, sets
  `input`, clears `result`, `output` and the banner. `ServiceProvider.handle` calls it instead of
  `startProcessing()` (busy case unchanged: banner, input kept). Update `ServiceProviderTests`
  (`polishLoadsTextStartsProcessingAndActivates` → loads, does not start, activates) and the doc
  comments/README/`docs/next-steps.md` that say the service starts polishing.
- **Summary toggle**: `AppModel.includesLearningSummary` persisted in UserDefaults key
  `learningSummaryEnabled` (default true, `didSet` like `channel`), passed to `polish`. When off:
  no Learning Summary card, one skeleton card, idle hint "Your polished text will appear here."
- **Progressive display**: the `onPreview` closure hops to the main actor and calls
  `showPreview(_:generation:)`, ignored unless that generation is still the running polish and no
  final result has arrived. A preview sets `result` (summary nil), `output`, and
  `isAwaitingSummary`. The final result then sets `result` but leaves `output` alone (keeps edits
  made meanwhile). Copy works while the summary is pending (it only needs `result`); Refine/Polish
  stay disabled until the request ends. Cancel or failure after a preview keeps the polished text
  on screen and records the history entry without a summary (failure also shows the banner).
  History and learning log are written once, at the end. `ResultsView.phase`: skeleton only while
  there is no result; with `isAwaitingSummary`, show `PolishedCard` + a redacted summary card.
  Scroll-to-results fires on the preview.
- **Tokens**: `AppModel` holds the shared `UsageStore` and a `monthlyUsage` refreshed at launch and
  after every request ends (`finishRequest`). Toolbar item next to `HistoryButton`: "48.2K tokens
  this month" (compact format), `.help` with the breakdown. `WritingAssistantApp` builds one
  `UsageStore` and passes it to both `PolishService` and `AppModel`; `AppModel.testing(...)` uses a
  temp dir.
- **Settings › General** (first tab): Toggle "Show English learning summary" bound to the model;
  "This month" section with total, input, output, cache write, cache read, request count.
- **Refine row**: wrap the five buttons with the existing `FlowLayout` so they wrap at the 600 pt
  minimum width.
- Tests (`AppModel.testing(polisher:)`, `TestDefaults.make()` only): preview-then-final, final
  without preview, stale preview after final/cancel ignored, edits during pending kept, cancel and
  failure after preview, toggle persisted and passed through, usage refreshed, `loadInput` clears
  old result.

## Integration (main session)

Merge W1–W3, run checks, update `docs/architecture.md` (stream-json pipeline, usage.json, summary
toggle, service no longer auto-starts), `docs/next-steps.md` live checklist, README. Code review
pass, fix findings, `scripts/build_app.sh`, draft PR (gh pr create separate from push).

## Verification

- `swift build` (zero warnings), `scripts/test.sh`, `swift format lint -r Sources Tests`, prek hooks.
- Mutation sanity: break the scanner's escape handling and the "retry only before deltas" rule;
  confirm tests fail.
- Live, installed app (`scripts/build_app.sh`, launched from Finder):
  - Select text in another app → Services shortcut: window comes forward with the text, nothing
    runs until Polish is clicked.
  - Long English paragraph: polished text appears while the summary card is still a skeleton;
    Copy works then; summary fills in; edits made in between survive.
  - Spanish text: no summary skeleton after the preview.
  - Toggle the summary off in Settings: no summary card, faster reply, nothing in the learning log.
  - Toolbar token count rises after a polish and a refinement; `usage.json` has the current month.
  - "More diplomatic" / "More assertive" visibly change tone; both prompts appear in Settings ›
    Prompts; the row wraps at minimum width.
  - Logs: `/usr/bin/log stream --predicate 'subsystem == "local.writing-assistant"'`.
