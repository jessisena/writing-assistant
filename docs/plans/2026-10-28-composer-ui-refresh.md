# Composer UI refresh: Writing Assistant main window

## Context

The main window (`MainWindowView` → `Header` + `ComposerView` + `ResultsView`) works but reads
as a stack of default controls. The input box looks like any other text field, the toolbar
floats above it, the channel list takes as much room as the input, the main button says
"Process", the app uses the stock blue, and the diff relies on red/green alone. The goal is a
composer where the text is the focus and the next step is obvious, an ink-and-proofreading
look that belongs to a writing tool, a diff you can read at a glance, and small responses to
each action. It should still feel like a Mac app: keyboard shortcuts, light/dark mode and
Reduce Motion all keep working. No new accessibility work or checks are in scope. The
existing accessibility labels stay as they are.

## Analysis of the current screen

| # | Problem | Where | Effect |
|---|---------|-------|--------|
| 1 | The 34pt title repeats the app name, and the subtitle explains how to use the app | `WritingAssistantApp.swift:147` `Header` | ~70pt used before the text box |
| 2 | Toolbar icons sit outside the editor's border | `ComposerView.swift:11-18` | Looks like a separate control |
| 3 | Six vertical radio buttons (~130pt), with "Channel" as the label | `ComposerView.swift:20-25` | Takes as much room as the text, hard to scan. "Channel" is the app's internal word |
| 4 | "Process" doesn't say what happens. Main button on the left, Clear on the right. Extra "or ⌘↵" text | `ComposerView.swift:46-79` | Weak call to action, opposite of the usual macOS order |
| 5 | Channel resets to Formal on every launch | `AppModel.swift:18` | You pick it again every time |
| 6 | Empty area below the composer | `ResultsView` shows nothing when idle | No hint of what comes next |
| 7 | All-caps card titles, monospace model name | `ResultsView.swift:54, 91, 239` | Generic look, no clear order of importance |
| 8 | Stock system blue, plain grey cards | everywhere | Nothing ties the look to writing or editing |
| 9 | Diff uses red/green text only. Added text has no non-colour cue. "Show changes" is a toggle that swaps the editor out and the height jumps | `DiffView.swift:22-44`, `ResultsView.swift:94-118` | Hard for colour-blind users, no count of changes, the layout shifts |
| 10 | No feedback while waiting (Sonnet takes 8–19 s), Copy only changes its text, Clear can't be undone, no sign of the 20,000-character limit until it fails | `ComposerView`, `ResultsView`, `PolishService.swift:6` | The app feels unresponsive, and a mistaken Clear loses the text |

## Design direction

**Idea:** a writing desk. The editor, formatting bar, "Writing for" chips and Polish button
form one *sheet* of paper on a slightly darker *desk*. Colour comes from a writer's tools:
blue-black fountain-pen **ink** for actions, a proofreader's **red pencil** for removed
text, and a **green margin pen** for added text. The bold part is the sheet and the
proofreading-mark diff. Everything else stays quiet.

### Colour tokens (new `Theme.swift`, dynamic `NSColor(name:dynamicProvider:)`, no asset catalog)

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `ink` | `#33378A` | `#A9ADF2` | App tint: Polish button, selected chip, focus edge, links, vocabulary terms |
| `paper` | `#FDFDFC` | `#1F2024` | Sheet and card backgrounds |
| `desk` | `#EDEFF3` | `#141519` | Window background behind the sheet |
| `rule` | `#D9DCE3` | `#34363D` | Hairline dividers and sheet border |
| `redPencil` | `#B3263E` | `#FF8597` | Removed text and the tint behind it (12%) |
| `marginGreen` | `#1D7A52` | `#63D6A3` | Added text and the tint behind it (14%) |

The window uses `.tint(Theme.ink)`, so the app no longer follows the system accent colour.
That's the trade-off for having its own look.

### Type
SF Pro only. Editor and diff body 15pt with 1.35 line spacing. Card titles `.headline` in
sentence case. Model name `.caption` in secondary colour, not monospace.

### Layout (left-aligned, max width 720)

```
desk ─────────────────────────────────────────────────────────
│ Writing Assistant                            [History]       │ ← window title
│ ╭─ paper ────────────────────────────────────────────────╮  │
│ │ B  I  S  </>  ≡  │ ☺                                    │  │
│ │────────────────────────────────────────────────────────│  │
│ │ Paste or type the text you want to polish…             │  │ min 220pt
│ │────────────────────────────────────────────────────────│  │
│ │ Writing for (Slack)(Casual Slack)(Talking points)      │  │ chips wrap
│ │             (Formal doc)(AI prompt)(General)           │  │
│ │ 1,204 / 20,000                  Clear   [ Polish  ⌘↵ ] │  │
│ ╰────────────────────────────────────────────────────────╯  │
│                                                              │
│ Polished text   English · Sonnet   [Edit|Changes]  [Copy]    │
│ ╭─ paper ────────────────────────────────────────────────╮  │
│ │ I'll ~~will~~ review the doc today ~~tomorrow~~ …      │  │
│ │ 6 changes   ■ removed  ■ added                         │  │
│ ╰────────────────────────────────────────────────────────╯  │
```

**Check against generic defaults:** an early draft gave every section its own rounded card
with a soft shadow, the stock SaaS card look. I changed it to one sheet with hairline
dividers, flat cards with a `rule` border, and no shadows or gradients. I also dropped a
cream "paper" colour (a common AI-design default) for a cool off-white sheet on a blue-grey
desk.

## Changes

### A. Composer and layout
1. **Header** (`WritingAssistantApp.swift`): remove `Header`. Show the window title in the
   toolbar. The instructions move into the editor placeholder. Window background `desk`.
2. **Writing sheet** (`ComposerView.swift`): toolbar, editor and footer in one
   `VStack(spacing: 0)` with `Divider()`s, 12pt corners, `paper` fill, `rule` border.
   `RichTextEditor` (`RichTextEditor.swift:449-480`) gets `isBordered: Bool = true` so the
   sheet can draw its own border. The input `minHeight` becomes 220 and the font size 15pt.
   Placeholder: "Paste or type the text you want to polish…".
3. **"Writing for" chips:** a custom chip `ButtonStyle` (ink at 15% fill + ink border when
   selected, `rule` border otherwise, hover fill on the pointer) in a small `FlowLayout: Layout`
   so the chips wrap at the 600pt minimum width. Add `Channel.shortName` in `Contracts.swift`
   ("Slack", "Casual Slack", "Talking points", "Formal doc", "AI prompt", "General").
   `displayName` stays for History, the learning log and the `.help` tooltip.
4. **Action row:** "Process" becomes "Polish", with ⌘↵ shown as dim text inside the button.
   Order: character count, Spacer, Clear (`.borderless`, hidden when there's nothing to
   clear), Polish (`.borderedProminent`). Cancel replaces Clear while a request runs.
5. **Remember the channel:** keep `channel` in `UserDefaults` (key `selectedChannel`, raw
   value) through `AppModel`. `AppModel.testing(polisher:)` gets a temporary
   `UserDefaults(suiteName:)` so tests never touch the real settings.
6. **Idle hint** (`ResultsView.swift`): with no result and no request running, show
   "Your polished text and a short English tip will appear here." in secondary colour.
7. **Result cards:** `paper` fill, `rule` border. Titles in sentence case `.headline` (drop
   `.uppercased()` at lines 54 and 239). Language and model in one caption line, with the
   "Translated from …" capsule in `ink`. `GrammarInsight` uses an ink edge and an ink fill at
   6%. Vocabulary terms in `ink`.

### B. Diff view (`DiffView.swift`, `ResultsView.swift:94-118`)
8. **Proofreading marks:** removed = `redPencil` + strikethrough + 12% tint behind it.
   Added = `marginGreen` + single underline + 14% tint behind it. Same 15pt font and line
   spacing as the editor.
9. **Legend and count:** a footer line inside the card: "6 changes · ■ removed ■ added", or
   "No changes" when the text is the same. Add `DiffDisplay.changeCount(_:)` (counts runs of
   removed/added segments, so a removed + added pair counts as one change) with unit tests.
10. **Edit | Changes switch:** replace the "Show changes" toggle with a two-item segmented
    `Picker` bound to `showsChanges`. Hidden for translations, as now. The diff gets the
    editor's current height as its `minHeight` so switching doesn't make the layout jump,
    and the two views cross-fade (`.transition(.opacity)`, no animation with Reduce Motion).

### C. Micro-interactions (each one responds to something you do; all respect Reduce Motion)
11. **Polishing feedback:** while a request runs, the button shows a spinner + "Polishing…".
    After 5 s it adds the elapsed time ("Polishing… 9 s") through a `TimelineView` reading a
    new `requestStartedAt: Date?` on `AppModel` (set in `startProcessing`, cleared when the
    request ends or is cancelled).
12. **Results arrival:** the skeleton changes into the result with one fade + 6pt upward move
    (`.transition(.opacity.combined(with: .offset(y: 6)))`), only when the result arrives.
13. **Copy:** the icon changes from `doc.on.doc` to `checkmark` with
    `.contentTransition(.symbolEffect(.replace))` and the label "Copied", and a light
    trackpad haptic plays (`NSHapticFeedbackManager.defaultPerformer.perform(.alignment,
    performanceTime: .now)`). It goes back after `copiedDuration`, as now.
14. **Chip selection:** the selected fill changes with `.animation(.snappy(duration: 0.15))`.
    The pointer gets a hover fill.
15. **Editor focus:** the sheet border turns `ink` at 60% while the input editor has focus.
    `FormattingTextView` tells `RichTextController` when it gains or loses first responder
    status (`isFocused` @Observable property).
16. **Undoable Clear:** `clear()` saves the input, output and result and registers an undo
    action with the window's `UndoManager`, so ⌘Z (and Edit ▸ Undo Clear) brings them back.
17. **Length meter:** the footer shows "1,204 / 20,000" (from
    `PolishService.maxInputLength`) only after 15,000 characters. It turns `redPencil` past
    the limit, and Polish is then disabled with a tooltip explaining why.
18. **Refine progress:** the refinement button that is running shows a small spinner in
    place of its label. The other refinement buttons stay disabled, as now.

Out of scope: a new font, the History and Settings windows (they pick up `ink` through the
tint but get no layout changes).

## Execution

The main session runs the work. It gives the tasks to subagents (`engineering:senior-software-engineer`,
each in its own `isolation: "worktree"`), merges their branches, and checks the result. A
subagent never edits a file that another subagent in the same wave owns.

**Step 0 (main session):** create the branch `feat/NOJIRA-000_composer_ui_refresh` from
`origin/main`. Save this plan as `docs/plans/2026-10-28-composer-ui-refresh.md` and commit it
(`docs(NOJIRA-000): add composer ui refresh plan`). Push, so the worktrees can branch from it
(`git switch -c <name> feat/NOJIRA-000_composer_ui_refresh`).

**Wave 1, foundation (one subagent, because everything after it depends on its interfaces):**
- `Theme.swift` colour tokens.
- `Channel.shortName` + tests.
- `RichTextEditor`: `isBordered`, the 15pt font and line spacing, and `RichTextController.isFocused`.
- `AppModel`: keep the channel (test defaults suite), `requestStartedAt`, and an undoable
  `clear(undoManager:)`, with tests.
- `DiffDisplay.changeCount` + tests.
- Output: the exact names and signatures of these APIs, which the main session passes to Wave 2.

**Wave 2, two subagents in parallel, branched from the merged Wave 1:**

| Subagent | Owns | Items |
|----------|------|-------|
| Composer | `ComposerView.swift`, `WritingAssistantApp.swift`, new `FlowLayout.swift` | 1–5, 11, 14, 15, 16 (UI side), 17 |
| Results & diff | `ResultsView.swift`, `DiffView.swift` | 6–10, 12, 13, 18 |

Each subagent runs `swift build`, `scripts/test.sh` and `swift format lint` before it
reports. It commits with `type(NOJIRA-000): …` subjects.

**Wave 3 (main session):** merge both branches, fix any conflicts, and run the full
verification below. Then one `engineering:code-reviewer` subagent reviews the whole diff.
Apply its fixes, update `docs/plans/2026-10-28-composer-ui-refresh.md` if anything changed,
push, and open a draft PR.

## Critical files

- `Sources/WritingAssistant/Theme.swift` (new): colour tokens
- `Sources/WritingAssistant/ComposerView.swift`: sheet, chips, `FlowLayout`, action row, meter
- `Sources/WritingAssistant/DiffView.swift`: marks, legend, `changeCount`
- `Sources/WritingAssistant/ResultsView.swift`: cards, Edit|Changes switch, copy, transitions,
  idle hint, refine progress
- `Sources/WritingAssistant/RichTextEditor.swift`: `isBordered`, font size, focus reporting
- `Sources/WritingAssistant/WritingAssistantApp.swift`: remove `Header`, tint, desk background
- `Sources/WritingAssistant/AppModel.swift`: keep channel, `requestStartedAt`, undoable clear
- `Sources/WritingAssistantCore/Contracts.swift`: `Channel.shortName`

Reuse: `RequestRunner` for the running state, `DiffDisplay`/`TextDiff.words` for segments,
`AppModel.copiedDuration`, `PolishService.maxInputLength`.

## Verification

- `swift build`, `scripts/test.sh`, `swift format lint -r Sources Tests`. All must run with
  no warnings.
- New tests: `Channel.shortName`. The channel is kept across `AppModel` instances that share
  the same test defaults suite. `requestStartedAt` is set on start and cleared on finish and
  cancel. Clear + undo restores the input, output and result. `DiffDisplay.changeCount`
  covers empty input, no changes, adjacent removed + added, and whitespace-only changes.
- Break-the-code check: change `changeCount` to count segments instead of runs, and confirm
  a test fails.
- `scripts/build_app.sh`, then take screenshots in light and dark mode at 600pt and 820pt
  wide. Check the chips wrap, that ⌘↵ / ⌘K / Esc / ⌘Z work, and that the Polishing timer
  appears after 5 s. With Reduce Motion on, check that the transitions are instant.

## Changes made during implementation

- During a refinement, the result stays on screen at 50% opacity and can't be edited. The
  refinement button that is running shows a spinner. The skeleton only shows for a polish
  request.
- The Polish button stays enabled while a request runs, because the disabled style made the
  label hard to read. A click or ⌘↵ during a request does nothing: `AppModel` and
  `RequestRunner` reject a second start. The button is disabled only over the length limit.
- The Polish label uses `Theme.paper` so it stays readable on the light dark-mode ink.
- The length meter counts what `PolishService` checks: the unicode scalars of the trimmed
  Markdown. The count is cached and updated when the input changes.
- Clear makes the window's first responder resign before it registers the undo, so ⌘Z
  reaches the window's undo manager instead of the editor's emptied stack. Undoing a Clear
  saves the newer output to History first.
- Restoring a History entry also saves its channel as the next-launch selection.
- Test `UserDefaults` suites are removed when the test process exits.
