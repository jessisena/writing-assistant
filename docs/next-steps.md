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
confirm the invariant tests fail, then restore it.

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

## 5. Copy

Click Copy on the Polished Text card. The button reads "Copied" for about 2 seconds and the
polished text is on the clipboard.

## 6. Keyboard-only pass

- Tab reaches the text input, the channel radio group, the Process button and Copy.
- Arrow keys move between the six channel options.
- ⌘↩ submits from the text input.
- Focus rings are visible throughout.
- The skeleton shows while a request runs, and the window stays responsive.
- The layout holds at the minimum window size (600×500) and when wide.

## 7. Prompt editor (Settings, ⌘,)

- The sidebar lists Global rules and the six channels.
- Edit `slack.txt` in the app: the unsaved-changes dot appears. Save (⌘S), process with the Slack
  channel, and confirm the output reflects the change.
- Revert discards unsaved edits.
- Remove `{{CHANNEL_GUIDELINES}}` from Global rules and save: an inline error appears and the file
  on disk is unchanged.
- Clear a channel file and save: an inline error appears and nothing is saved.
- Restore Default on an edited file: an inline confirmation appears, and confirming brings back
  the bundled text.
- Reveal in Finder opens `~/Library/Application Support/Writing Assistant/prompts/`.
- Edit a file in an external editor, then process: the next request uses the edit with no
  relaunch.
- Delete one file in that folder and relaunch: only that file is re-seeded; your other edits stay.

---

## Model upgrade check

Check whether a newer Sonnet is available to the CLI:

```sh
claude --print --model claude-sonnet-5 "hi"
```

If it succeeds, update `sonnetModel` in `Sources/WritingAssistantCore/ModelRouting.swift` and
rebuild with `scripts/build_app.sh`.
