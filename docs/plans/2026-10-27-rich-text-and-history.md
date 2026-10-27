# Rich text input, editable formatted output, Clear button

## Context

Today both text areas are plain: the input is a `TextEditor(text: String)`
(`Sources/WritingAssistant/ComposerView.swift:24`) and the output is a read-only
`Text(result.polishedText)` (`Sources/WritingAssistant/ResultsView.swift:94`). Claude often returns
Markdown (`**bold**`, `- bullets`), which shows up as raw asterisks, and Copy puts only a plain
string on the clipboard (`AppModel.writeToGeneralPasteboard`), so pasting into Slack loses all
formatting.

Requested:

1. Formatting in the input (bold, italic, etc. and emoji).
2. An editable output that keeps its formatting and emoji when pasted into Slack.
3. A Clear button.

You also picked these improvements from the earlier recommendations: cancel a running request,
prompt default update notice, quick refinements, diff view, learning log, polish from anywhere,
history.

Decisions made: wrap AppKit `NSTextView` (keep macOS 14 as the minimum). Clear resets input,
result, learning summary and error.

**Delivery:** a main session runs the work. It hands the phases to subagents that run in parallel
where the files they touch don't overlap (see **Execution** at the end). Phases A–C are what you
asked for; D–J are the improvements. This plan is stored in the repo at
`docs/plans/2026-10-27-rich-text-and-history.md`, and the subagents work from that copy.

## Core idea: Markdown is the format the app and Claude exchange

The editors hold `NSAttributedString`. On Process, the input is converted to Markdown and sent to
Claude. Claude returns Markdown in `polished_text`, which is parsed into an attributed string for
the output editor. Copy turns the edited output into HTML (Slack keeps bold, italic, strikethrough,
code, links and lists when you paste HTML) plus a plain-text fallback. `PolishResult.polishedText`
stays a `String`; only its content changes.

Supported subset (kept small, matching what Slack can render): bold, italic, strikethrough,
inline code, links (kept from pasted text, no editor button), bullet lists, headings (for the
Formal channel; they paste into Slack as bold lines). Emoji are plain Unicode and need no
conversion.

---

## Phase A: Rich text conversion (Core)

New `Sources/WritingAssistantCore/RichText.swift`, Foundation only. It works on `AttributedString`
with `inlinePresentationIntent` (`.stronglyEmphasized`, `.emphasized`, `.strikethrough`, `.code`)
and `link`:

- `attributedString(fromMarkdown:)`: parse each line with
  `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))`;
  handle block syntax per line (`- `/`* ` → `• ` bullet, `#`… → heading attribute). If a line
  fails to parse, keep it as plain text. Never throw, since model output is untrusted.
- `markdown(from:)`: the reverse, used for requests.
- `html(from:)`: `<b>`, `<i>`, `<s>`, `<code>`, `<a href>`, consecutive bullets → one
  `<ul><li>`, headings → `<b>` paragraphs, `<br>` line breaks, all text HTML-escaped.
- `plainText(from:)`: markers removed, bullets kept as `•`. This is the clipboard fallback and
  the input for the diff (Phase G).

Tests in `Tests/WritingAssistantCoreTests/RichTextTests.swift`: a table of round-trip cases (bold,
italic, nested bold+italic, strike, code, link, bullets, heading, ZWJ emoji and flags, CJK, empty,
unbalanced `**`, a literal `*`), HTML escaping (`<script>`, `&`), bullet grouping, plain-text
output.

## Phase B: Rich text editors, editable output, Slack-friendly copy

New `Sources/WritingAssistant/RichTextEditor.swift` (split the toolbar out if it goes over the
function or line limits):

- `RichTextBridge`: `NSAttributedString` (font traits, `.strikethroughStyle`, monospaced font,
  `.link`) ↔ `AttributedString` (intents). It is also used to **normalize pasted text**: pasting
  from Docs or Slack keeps bold, italic, strike, code and links, and drops foreign fonts, sizes and
  colors. Foreground is `NSColor.textColor` so dark mode works.
- `FormattingTextView: NSTextView`: rich text, undo, no images, spell check. It has
  `toggleBold/Italic/Strikethrough/Code/Bullet` actions and overrides `paste(_:)` to normalize.
- `RichTextEditor: NSViewRepresentable` in an `NSScrollView`, bound to `NSAttributedString`,
  taking over the placeholder and border styling from `InputEditor`. It only sets the text storage
  when the binding differs from what is shown, to avoid update loops.
- `RichTextController` (holds its text view weakly) so each toolbar acts on its own editor.
- `FormattingToolbar`: Bold, Italic, Strike, Code, Bullet, Emoji
  (`NSApp.orderFrontCharacterPalette`). Each button gets an accessibility label and a help tooltip
  with its shortcut.
- `CommandMenu("Format")` in `WritingAssistantApp` with ⌘B, ⌘I and ⌘⇧X. It sends to the first
  responder (`NSApp.sendAction(_:to: nil, from:)`), so it acts on the focused editor.

`AppModel`:
- `inputText: String` → `input: NSAttributedString`. Requests send `RichText.markdown(from:)`.
- New `output: NSAttributedString`, set from `result.polishedText` on success and freely editable
  after that.
- `copyResult()` copies the **edited** `output`. `writeToPasteboard` takes
  `ClipboardContent { html, plain }`, and the default writes `.html` + `.string`.

Views: `ComposerView` gets the toolbar and editor. `ResultsView.PolishedCard` becomes a toolbar
plus an editor bound to `model.output`. `Fakes.swift` gets a sample result with Markdown.

Prompts: `polish.txt` gets an "Input format" note (the input may contain the Markdown subset and
emoji; keep the author's emoji and emphasis unless channel rules say otherwise) and an "Output
format" rule (`polished_text` uses only that subset, with no tables, fences or HTML). Update the
JSON examples to match. `slack.txt` and `slack_informal.txt` say to use Markdown bold, italic and
bullets (converted for Slack on copy), so the model doesn't emit Slack's `*bold*` mrkdwn, which
would parse as italic. Phase E delivers the changed defaults to the installed app.

Tests: `Tests/WritingAssistantTests/RichTextBridgeTests.swift` covers traits ↔ intents and paste
normalization. `AppModelTests` covers: formatted input is sent as Markdown, the output is set from
the result, and copy writes HTML and plain text from the edited output. Update the existing tests
that use `inputText` or the `String` pasteboard closure.

## Phase C: Clear

- `AppModel.clear()` resets input, output, result and errorMessage, and does nothing while a
  request is running. `canClear` is false while loading or when everything is already empty.
- A `Clear` button in `ProcessRow` (bordered, ⌘K, disabled unless `canClear`).
- Tests: clear resets everything, it does nothing while loading, and `canClear` is correct in each
  state.

## Phase D: Cancel a running request

- The model owns the request task. `AppModel.startProcessing()` stores a `Task` and runs
  `process()`; `cancel()` cancels it. `ClaudeCLI` already terminates the child on task
  cancellation (`withTaskCancellationHandler` in `ClaudeCLI.run`).
- After a cancel, check `Task.isCancelled` and show no error banner, just the previous empty state.
  Don't match on the internal `"Cancelled"` string.
- UI: while loading, a `Cancel` button replaces Clear, with `.keyboardShortcut(.cancelAction)`
  (Esc).
- Tests: a fake polisher that suspends until cancelled. Check that cancel ends loading with no
  error and no result, and that a new request after a cancel works.

## Phase E: Prompt default updates

Live prompts are seeded only once, so changed bundled defaults (Phase B, Phase F) never reach an
installed app. Fix this in `PromptStore`:

- Keep a manifest at `prompts/.defaults.json` mapping each `relativePath` to the SHA-256
  (CryptoKit) of the bundled default it was last seeded or restored from. `seedMissingDefaults`
  and `restoreDefault` write it.
- New `PromptStoring.syncDefaults() throws -> Set<PromptFile>`, run at launch after seeding:
  - User file unchanged from its recorded default and bundled default changed → overwrite it
    silently and update the manifest.
  - User file edited and bundled default changed → leave it and return the file as "newer default
    available".
  - No manifest entry (current installs): if the file matches the bundled default, record it;
    otherwise report it as "newer default available".
- New `acknowledgeDefault(_:)` records the current bundled hash without touching the file
  ("Keep mine").
- Settings: a badge on affected sidebar rows, and a banner in the editor ("A newer default is
  available") with **Restore Default** (uses the existing confirm flow) and **Keep mine**.
  `PromptEditorModel` holds the set.
- Tests in `PromptStoreTests` (temp directories): each of the three branches, a corrupt manifest
  (treated as missing and rewritten, no crash), and acknowledgement.

## Phase F: Quick refinements

- `Contracts.swift`: `enum Refinement: CaseIterable { shorter, moreCasual, moreFormal }` and
  `PromptFile.refinement(Refinement)` → `refinements/<name>.txt`. Bundle default instruction files
  in `Resources/Prompts/refinements/`. They can be edited in Settings, which lists them in their
  own sidebar section.
- `Polishing.refine(text:channel:refinement:) async throws(PolishError) -> String`. It uses the
  same assembled prompt plus an appended "Additional instruction" section and returns only the new
  `polished_text`. `PolishService` reuses `validatedInput`, `assemblePrompt` and `parse`.
- `AppModel.refine(_:)` sends the current **edited** output as Markdown and replaces `output`. It
  keeps the original learning summary and language, since a summary of the model's own text would
  be meaningless. It shares the loading, cancel and error paths with `process()`.
- UI: a row of three buttons under the Polished Text card, disabled while loading.
- Tests: pipeline tests check that the instruction is in the prompt and only the polished text
  changes. AppModel tests check that the edited output is what gets sent and the summary is kept.

## Phase G: Diff view

- Core `TextDiff.words(from:to:) -> [DiffSegment]` (`.same`, `.added`, `.removed`), tokenised on
  words + whitespace, using the standard library's `difference(from:)`. Both sides go through
  `RichText.plainText` first.
- UI: a "Show changes" toggle in the Polished Text header that swaps the editor for a read-only
  diff of input against current output: removed text red with strikethrough, added text green.
  Colors come with a text alternative for VoiceOver ("removed: …"). Hidden when `wasTranslated`
  is true, because a translation diff means nothing.
- Tests: identical text, all added, all removed, a middle replacement, whitespace-only changes,
  emoji tokens.

## Phase H: Learning log

- Core `LearningLog` in `~/Library/Application Support/Writing Assistant/learning-log.md`.
  `entry(for:channel:date:) -> String` is a pure formatter (date heading, corrections as
  `original → corrected: why`, insight, vocabulary). `append(_:)` creates the file if needed and
  appends.
- `AppModel` appends after a successful `process()` when the summary is non-nil and non-empty.
  Refinements never append. If writing fails, show the error in the banner but keep the result.
- "Open Learning Log" in the app menu (`NSWorkspace.shared.open`).
- Tests: formatter output, skips empty or nil summaries, append to a temp file twice keeps both
  entries, unwritable directory surfaces an error.

## Phase I: History

- Core `HistoryEntry: Codable` (id, date, channel, input Markdown, output Markdown, learning
  summary, detected language, wasTranslated, model). `HistoryStore` reads and writes
  `history.json` in Application Support atomically and keeps the newest 50. A corrupt file is
  renamed to `history.corrupt.json` and the store starts empty, and the app reports it in the
  banner.
- `AppModel` records an entry when a request succeeds. It saves the current edited output into
  that entry on copy, refine, clear and before the next request, so edits aren't lost and it
  doesn't write on every keystroke.
- UI: a History button (⌘Y) opens a popover listing the entries (relative date, channel, first
  line). Selecting one restores the input, output and summary. Each row has Delete, and there's
  "Clear History" with an inline confirm (the same pattern as Restore Default).
- Tests: cap at 50, round trip, corrupt file, restore puts everything back into the model, and
  edits are saved on copy and clear.

## Phase J: Polish from anywhere (macOS Service)

- `Resources/Info.plist`: an `NSServices` entry "Polish with Writing Assistant" accepting
  `public.utf8-plain-text` and `public.rtf`, with no return type. In-place replacement would block
  the calling app for the 8–20 s a request takes, and services time out.
- `ServiceProvider` (set as `NSApp.servicesProvider` in `AppDelegate`): reads the pasteboard
  (rich text goes through `RichTextBridge` normalization), brings the window forward, loads the
  text into `input` and calls `startProcessing()` with the current channel. If a request is
  already running, it shows a banner and doesn't replace it.
- `scripts/build_app.sh`: run `/System/Library/CoreServices/pbs -update` after installing so the
  service appears right away. Document assigning a shortcut in System Settings → Keyboard →
  Keyboard Shortcuts → Services.
- Tests: the provider's pasteboard → model path with a fake pasteboard (plain and RTF), and the
  busy case.

---

## Shared interfaces

Workers that run at the same time build against these signatures, so they don't wait on each
other. A worker that has to change a signature reports it back to the main session instead of
changing it on its own.

```swift
// Core: Phase A
public enum RichText {
    static func attributedString(fromMarkdown: String) -> AttributedString
    static func markdown(from: AttributedString) -> String
    static func html(from: AttributedString) -> String
    static func plainText(from: AttributedString) -> String
}
// Core: Phase E (added to PromptStoring)
func syncDefaults() throws -> Set<PromptFile>   // files with a newer default the user hasn't taken
func acknowledgeDefault(_ file: PromptFile) throws
// Core: Phase F
public enum Refinement: String, CaseIterable, Sendable, Identifiable { case shorter, moreCasual = "more_casual", moreFormal = "more_formal" }
case PromptFile.refinement(Refinement)          // refinements/<rawValue>.txt
func Polishing.refine(text: String, channel: Channel, refinement: Refinement) async throws(PolishError) -> String
// Core: Phase G
public struct DiffSegment: Equatable, Sendable { enum Kind { case same, added, removed }; let kind: Kind; let text: String }
public enum TextDiff { static func words(from: String, to: String) -> [DiffSegment] }
// Core: Phase H
public struct LearningLog { init(fileURL: URL); static func standard() -> LearningLog
    static func entry(for: LearningSummary, channel: Channel, date: Date) -> String
    func append(_ summary: LearningSummary, channel: Channel, date: Date) throws }
// Core: Phase I
public struct HistoryEntry: Codable, Equatable, Sendable, Identifiable { … }
public struct HistoryStore { init(fileURL: URL, limit: Int = 50); static func standard() -> HistoryStore
    func load() throws -> [HistoryEntry]        // corrupt file: moved aside, throws HistoryStoreError.corrupted(backup:)
    func save(_ entries: [HistoryEntry]) throws }
// App: Phases B–D
AppModel.input / .output: NSAttributedString; startProcessing(); cancel(); clear(); canClear
struct ClipboardContent { let html: String; let plain: String }
RichTextBridge.attributedString(from: NSAttributedString) -> AttributedString, .nsAttributedString(from:), .normalized(_:)
```

## Execution (main session + parallel subagents)

### Ground rules for every worker

- Spawned with the Agent tool, `isolation: "worktree"`, each on its own branch named
  `feat/NOJIRA-000_<snake_case>` (the commit hooks need that branch format).
- The prompt gives: the plan path, the phase(s) to do, the **files it owns**, the files it must
  not touch, and the shared interfaces above.
- Tests come first. Before reporting, run `swift build` (zero warnings), `scripts/test.sh` and
  `swift format lint -r Sources Tests`, plus shellcheck/shfmt if it touched a script.
- Commit subjects use `type(NOJIRA-000): lowercase desc`, one logical change each. Workers never
  push or open PRs.
- The report back has: the branch, the commits, the test count, any change to an interface, and
  anything it skipped or left open.

### Wave 0: main session (sequential)

1. `git fetch origin`, then branch `feat/NOJIRA-000_rich_text_and_history` from `origin/main`.
2. Copy this plan to `docs/plans/2026-10-27-rich-text-and-history.md` and commit it
   (`docs(NOJIRA-000): add rich text and history plan`).
3. Run the baseline: `swift build && scripts/test.sh`, which should give 132 passing tests.

### Wave 1: four workers in parallel (Core-only, no overlapping files)

| Worker | Phases | Owns |
|---|---|---|
| `rich-text-core` | A | `RichText.swift`, `RichTextTests.swift` |
| `prompt-sync` | E | `PromptStore.swift`, `PromptStoring` in `Contracts.swift`, `FakePromptStore` in `Fakes.swift`, `PromptEditorModel/View.swift`, their tests |
| `refine-core` | F (Core part) | `Refinement` + `PromptFile` + `Polishing` in `Contracts.swift`, `PolishService.swift`, `Resources/Prompts/refinements/`, `FakePolisher` in `Fakes.swift`, pipeline tests |
| `diff-log-history-core` | G, H, I (Core parts) | `TextDiff.swift`, `LearningLog.swift`, `HistoryStore.swift`, their tests |

`prompt-sync` and `refine-core` both edit `Contracts.swift` and `Fakes.swift`, but in different
declarations. The main session resolves any textual conflicts when merging.

**Merge gate:** merge each branch into the feature branch with `--no-ff`, in the order listed.
Rerun build, tests and lint after each merge. If a merge breaks something, the main session fixes
it, or uses SendMessage to send the failure back to that worker.

### Wave 2: one worker (the app-side foundation, which everything later builds on)

| Worker | Phases | Owns |
|---|---|---|
| `editors-clear-cancel` | B, C, D | `RichTextEditor.swift`, `FormattingToolbar.swift`, `AppModel.swift`, `ComposerView.swift`, `ResultsView.swift`, `WritingAssistantApp.swift` (Format menu), `polish.txt`, `slack*.txt`, `AppModelTests`, `RichTextBridgeTests` |

These three phases all change `AppModel` and `ComposerView`, so a single worker does them in
order, one commit per phase. This is the critical path. Meanwhile the main session reviews the
Wave 1 merges (code-review agent on the merged diff) and fixes what it finds.

### Wave 3: three workers in parallel (app integration)

| Worker | Phases | Owns |
|---|---|---|
| `refine-diff-ui` | F (UI), G (UI) | `AppModel+Refine.swift`, `DiffView.swift`, the Polished Text card in `ResultsView.swift` |
| `log-history-ui` | H (UI), I (UI) | `AppModel+History.swift`, `HistoryView.swift`, app menu items in `WritingAssistantApp.swift` |
| `service` | J | `ServiceProvider.swift`, `AppDelegate` in `WritingAssistantApp.swift`, `Resources/Info.plist`, `scripts/build_app.sh` |

To keep conflicts small, each worker puts its AppModel methods in its own `extension AppModel`
file. New stored properties (`@Observable` needs them in the class body) are the only edits to
`AppModel.swift`. Where `WritingAssistantApp.swift` is shared, edits go in separate declarations.

**Merge gate:** same as Wave 1. Merge order: `refine-diff-ui`, `log-history-ui`, `service`.

### Wave 4: main session (wrap-up)

1. Update `docs/next-steps.md` (the manual checklist below), `docs/architecture.md` and
   `README.md`.
2. Run one code-review agent over the full branch diff against `origin/main`, then fix the
   findings that are real.
3. Run the break-the-code checks, the full automated checks and `scripts/build_app.sh`.
4. Hand the manual checklist to the user. Push and open a draft PR only after the user confirms.

Total: 8 subagents plus 1 reviewer. At most four run at once.

## Files

New Core: `RichText.swift`, `TextDiff.swift`, `LearningLog.swift`, `HistoryStore.swift`,
`Resources/Prompts/refinements/*.txt`.
New app: `RichTextEditor.swift`, `FormattingToolbar.swift`, `DiffView.swift`, `HistoryView.swift`,
`ServiceProvider.swift`.
Modified: `Contracts.swift`, `PolishService.swift`, `PromptStore.swift`, `AppModel.swift`,
`ComposerView.swift`, `ResultsView.swift`, `WritingAssistantApp.swift`, `PromptEditorModel.swift`,
`PromptEditorView.swift`, `Fakes.swift`, `polish.txt`, `slack.txt`, `slack_informal.txt`,
`Resources/Info.plist`, `scripts/build_app.sh`, `docs/next-steps.md`, `docs/architecture.md`,
`README.md`. Tests are added or updated next to each change.

`AppModel` grows a lot. Keep each function within the limits by letting the Core stores own their
persistence. If AppModel goes past roughly 300 lines, move history into its own
`@Observable HistoryModel`.

## Verification

After each phase: `swift build` (zero warnings), `scripts/test.sh`,
`swift format lint -r Sources Tests`. Phases that touch shell scripts also run
`shellcheck scripts/build_app.sh && shfmt -i 2 -d scripts/build_app.sh`. Break-the-code check:
remove HTML escaping, bullet grouping, the "edited file is kept" sync branch and the history cap
one at a time, and confirm a test fails for each.

At the end, run `scripts/build_app.sh` and launch from Finder. Then go through these manual checks
and add them to `docs/next-steps.md`:

- **Formatting:** use ⌘B/⌘I, the toolbar buttons and the emoji picker, then Process; the output
  keeps the emphasis and emoji. Paste from Google Docs: bold and italic are kept, fonts and colors
  are dropped.
- **Slack:** edit the output, Copy, and paste into a Slack DM to yourself. Bold, italic, strike,
  code, bullets and emoji show natively, and your edit is included. Paste into TextEdit and
  Terminal too.
- **Clear / Cancel:** ⌘K empties everything. Esc during a request stops it with no error banner,
  and `ps` shows no leftover `claude` process.
- **Prompt updates:** the first launch after the upgrade updates unedited prompts silently, and
  edited ones show the "newer default" banner.
- **Refine:** "Shorter" shortens the edited output and keeps the learning summary.
- **Diff:** additions and removals are highlighted, and the toggle is hidden for translated input.
- **Learning log:** English input with mistakes appends an entry, and Open Learning Log shows it.
- **History:** relaunch the app and the entries are still there. Restoring an entry brings back
  your edited output.
- **Service:** select text in Notes → Services → Polish with Writing Assistant; the app comes
  forward and processes it.
- Undo works in both editors, dark mode is readable, and VoiceOver reads the toolbar and diff.

## Not included

From the earlier recommendations, not picked: remembering the last channel (`@AppStorage`), and
live word/character counters with a model routing hint.
