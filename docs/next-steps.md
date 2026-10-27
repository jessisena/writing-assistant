# Next steps

Live verification checklist for the native app. Run the automated checks first, then go through
the live steps with the installed app.

---

## Automated checks

```sh
swift build                            # zero warnings
scripts/test.sh                        # all tests green
swift format lint -r Sources Tests     # clean
shellcheck scripts/build_app.sh && shfmt -i 2 -d scripts/build_app.sh
```

Mutation sanity check: temporarily remove the `was_translated` invariant in `PolishService` and
confirm the invariant tests fail, then restore it. Do the same, one at a time, for the HTML
escaping and bullet grouping in `RichText`, the "edited file is kept" branch of
`PromptStore.syncDefaults` and the 50-entry cap in `HistoryStore`.

---

## Install and launch

```sh
scripts/build_app.sh
```

Launch `Writing Assistant` from Finder or the Dock, not from a terminal. This proves the app finds
`claude` with the minimal `PATH` Finder gives it. Confirm:

- The window opens with no "claude CLI not found" banner.
- A real request completes.
- After a reboot, a request still completes. If it fails with "Claude returned an error", run
  `claude` once in a terminal to re-authenticate, then retry.

Watch the logs while testing:

```sh
/usr/bin/log stream --predicate 'subsystem == "local.writing-assistant"'
```

---

## 1. All six channels — Spanish input

Paste a Spanish paragraph and run it through all six channels. Verify:

- Each channel produces visibly different output (Slack: short and scannable; informal Slack:
  casual; talking points: spoken bullet list; formal: full paragraphs with headers; AI prompt:
  imperative and explicit; other: structure preserved).
- No learning summary appears in any of the six results; the summary area shows the
  translated-input message instead.
- No em dashes appear in any output (`—`).
- The Polished Text header shows the model used.

## 2. Language matrix

One paste each:

| Input | Expected |
|---|---|
| Spanish paragraph | Translated. Header shows "Translated from Spanish", highlighted. No learning summary. |
| Portuguese paragraph | Translated. Header shows "Translated from Portuguese". No learning summary. Confirms the rule is language-agnostic. |
| English with deliberate grammar mistakes | Not translated. Learning Summary lists accurate corrections (before → after, why), a grammar insight and vocabulary. |
| Already-correct English | Not translated. "Nothing to flag here — the text was already clean." or a near-empty summary, with no invented corrections. |
| Short English (≤60 words) | Header shows the Haiku model. |
| Long English or any non-English text | Header shows the Sonnet model. |

## 3. Translation fidelity

On the Spanish paste: confirm the meaning and intent survive translation, with no facts or figures
added that were not in the original.

## 4. Error paths

- Rename `~/.local/bin/claude` (and any other copy on your login shell `PATH`), then launch the
  app: the "claude CLI not found" banner appears at launch and again on Process. Rename it back.
- In a debug build, lower `PolishService.defaultTimeout` to 1 s and process some text: the
  "Claude took longer than 1 seconds" banner appears and the request is not retried. Restore it.
- Empty input: Process shows "Please paste some text before processing."
- Paste more than 20,000 characters: the too-long message appears and no request is sent.

## 5. Formatting

- In the input, use ⌘B, ⌘I and ⌘⇧X, each toolbar button (Bold, Italic, Strikethrough, Code,
  Bullet List) and the emoji picker, then Process. The output keeps the emphasis and the emoji.
- The Format menu items act on whichever editor has focus.
- Paste from Google Docs: bold and italic are kept, fonts, sizes and colors are dropped.

## 6. Copy and Slack paste

- Edit the output, then click Copy. The button reads "Copied" for about 2 seconds. The clipboard
  holds HTML and plain text built from the edited output.
- Paste into a Slack DM to yourself: bold, italic, strikethrough, code, bullets and emoji show
  natively, and your edit is included.
- Paste into TextEdit (formatted) and Terminal (plain text, bullets as `•`).

## 7. Clear and Cancel

- ⌘K empties the input, output, learning summary and error banner. Clear is disabled while a
  request runs and when everything is already empty.
- During a request, Cancel replaces Clear. Esc stops the request with no error banner, and
  `ps aux | grep claude` shows no leftover `claude` process.
- A new request after a cancel completes normally.

## 8. Refine

- "Shorter" shortens the edited output (not the original result) and keeps the learning summary.
- "More casual" and "More formal" change the tone. Esc cancels a running refinement.
- A refinement doesn't add a learning log entry.

## 9. Diff

- "Show changes" swaps the output editor for a read-only diff: removed text red with
  strikethrough, added text green. Turning it off brings the editor back with your edits.
- The toggle is hidden for translated input.

## 10. Learning log

- English input with mistakes appends an entry to
  `~/Library/Application Support/Writing Assistant/learning-log.md`.
- **Open Learning Log** in the app menu opens the file. Translated input and refinements add
  nothing.

## 11. History

- The History button (⌘Y) lists past requests with relative date, channel and first line.
- Edit an output, then process something else. Restoring the first entry brings back the input,
  your edited output and the learning summary.
- Relaunch the app: the entries are still there. Delete removes one row; Clear History asks for
  confirmation inline.
- Replace `history.json` with invalid JSON and relaunch: a banner reports it, the file is moved to
  `history.corrupt.json`, and history starts empty.

## 12. Service (polish from anywhere)

- Select text in Notes, then Notes → Services → **Polish with Writing Assistant**. The app comes
  forward and processes the selection with the current channel.
- Run it while a request is running: a banner explains that a request is already running, and
  the input is kept.
- Close the main window while Settings is open, then run the service: the main window opens again
  and processes the text.
- Quit the app and run the service: the app launches and processes the text.
- Assign a shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services → Text, and
  confirm it works.

## 13. Keyboard-only pass

- With Keyboard navigation on (System Settings → Keyboard), Tab reaches the formatting toolbars,
  the text input, the channel radio group, Process, Clear, History, Copy, Show changes and the
  Refine buttons.
- Arrow keys move between the six channel options.
- ⌘↩ submits from the text input.
- Focus rings are visible throughout.
- The skeleton shows while a request runs, and the window stays responsive.
- The layout holds at the minimum window size (600×500) and when wide.

## 14. Undo, dark mode and VoiceOver

- Undo and redo work in both editors, including after a formatting change and a paste.
- In dark mode, text in both editors, the diff and pasted text is readable.
- VoiceOver reads the toolbar buttons by name, and reads the diff as "removed: …" and
  "added: …".

## 15. Prompt editor (Settings, ⌘,)

- The sidebar has a Prompts section (Global rules and the six channels) and a Refinements section
  (Shorter, More casual, More formal).
- Edit `slack.txt` in the app: the unsaved-changes dot appears. Save (⌘S), process with the Slack
  channel, and confirm the output reflects the change.
- Revert discards unsaved edits.
- Remove `{{CHANNEL_GUIDELINES}}` from Global rules and save: an inline error appears and the file
  on disk is unchanged.
- Clear a channel file and save: an inline error appears and nothing is saved.
- Restore Default on an edited file: an inline confirmation appears, and confirming brings back
  the bundled text.
- Reveal in Finder selects the file in `~/Library/Application Support/Writing Assistant/prompts/`.
- Edit a file in an external editor, then process: the next request uses the edit with no
  relaunch.
- Delete one file in that folder and relaunch: only that file is re-seeded; your other edits stay.

## 16. Prompt default updates

- The first launch after an upgrade that changes a bundled prompt updates the files you haven't
  edited, with no notice.
- A file you edited keeps your text. Its sidebar row shows a badge, and the editor shows "A newer
  default is available" with **Restore Default** and **Keep mine**.
- **Keep mine** removes the badge and the banner, and they don't come back on relaunch.

---

## Known gaps

- Drag and drop and Edit → Paste and Match Style skip paste normalization, so dropped text can
  keep foreign fonts and colors.
- Return on a bullet line doesn't continue the list.
- Bold emoji may lose the bold in the Markdown sent to Claude.
- Bare URLs become links after a round trip through Claude.
- Refinements use the currently selected channel, not the channel of the original request.
- Image titles aren't kept.
