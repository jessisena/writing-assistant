# Next steps

Automated checks pass (49 tests, ruff, mypy). These are the remaining live verification steps and
the one outstanding install task.

---

## Live end-to-end testing

Start the desktop app (or the server alone for curl-based testing):

```sh
uv run python -m assistant.desktop        # full app: server + native window
uv run uvicorn assistant.main:app --host 127.0.0.1 --port 8765   # server only
```

### 1. All six channels — Spanish input

Paste a Spanish paragraph and run it through all six channels. Verify:

- Each channel produces visibly different output (Slack: short and scannable; talking points: spoken
  bullet list; formal: full paragraphs with headers; AI prompt: imperative and explicit; other:
  structure preserved).
- No learning summary appears in any of the six results.
- No em dashes appear in any output. (`—`)

### 2. Language-branch matrix

One paste each:

| Input | Expected |
|---|---|
| Spanish paragraph | Translated. `was_translated: true`. No learning summary. Card shows detected language. |
| Portuguese paragraph | Translated. `was_translated: true`. No learning summary. Confirms the rule is language-agnostic, not Spanish-specific. |
| English with deliberate grammar mistakes | Not translated. `was_translated: false`. Learning summary present and accurate. |
| Already-correct English | Not translated. `was_translated: false`. Graceful near-empty summary (not invented corrections). |

### 3. Translation fidelity

On the Spanish paste: confirm the meaning and intent survive translation with no facts or figures
added that were not in the original.

### 4. Error paths

- Rename `claude` on `PATH` (or temporarily set `PATH=""` in the server env) → should get a 503
  banner in the UI with a clear message.
- Lower `timeout` in `claude_cli.py` to 1s → should get a 504 banner.

### 5. Copy button

Click the Copy button on the Polished Text card — confirm the text lands on the clipboard.

### 6. Keyboard-only pass

- Tab reaches the textarea, the radio group, and the Process button.
- Arrow keys move between the six channel options.
- Cmd+Enter submits the form.
- Focus rings are visible throughout.
- Layout stays a single stack at both narrow and wide window widths.

---

## Launcher install + reboot test

This is the critical step — the launcher runs inside a `do shell script` environment that does
not load `~/.zshrc`, so `uv` and `claude` must be reachable via the explicit `PATH` in
`scripts/launcher.applescript`.

**Install:**

```sh
cd /path/to/writing-assistant
uv run --with pillow python scripts/make_icons.py   # generate icons (once)
bash scripts/build_launcher.sh                      # builds ~/Applications/Writing Assistant.app
```

**Reboot**, then click `Writing Assistant` in `~/Applications` (or the Dock). Confirm:
- The native window opens within ~5s.
- A real polish request completes successfully.

If it fails with "claude CLI not found", run `claude` once interactively to re-confirm OAuth, then
try the launcher again.

Logs: `tail -f ~/Library/Logs/writing-assistant.log`

---

## Model upgrade check

Verify whether `claude-sonnet-5` is available to the CLI:

```sh
claude --print --model claude-sonnet-5 "hi"
```

If it succeeds, update `SONNET_MODEL` in `assistant/routing.py`.
