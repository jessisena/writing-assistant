# Writing Assistant

A local macOS writing tool that polishes text for different channels (Slack, formal, talking points,
AI prompts) and produces an English learning summary when you write directly in English.

**Stack:** Python 3.12, FastAPI, vanilla HTML/JS/CSS frontend, pywebview for the native window, claude CLI for model calls.

**macOS only** — the launcher uses AppleScript and pywebview's Cocoa backend.

**Prerequisites:**
- [claude CLI](https://claude.ai/download) installed and authenticated (`claude --version` passes)
- [uv](https://docs.astral.sh/uv/) installed (`uv --version` passes)

**Privacy note:** the text you paste is sent to Anthropic's Claude model via your local `claude`
CLI subscription. No `ANTHROPIC_API_KEY` is needed or used. Input is bounded to 20,000 characters.
Like any LLM tool, the model output can be steered by crafted input (prompt injection); the
`was_translated` invariant is enforced server-side regardless of model output.

---

## Quick start (development)

```sh
uv sync
uv run uvicorn assistant.main:app --host 127.0.0.1 --port 8765
```

Then open **http://127.0.0.1:8765** in your browser.

---

## Install as a desktop app

The app runs as a native macOS window with a Dock icon. The server and UI are one process —
clicking the icon starts both, closing the window stops both immediately.

### Step 1 — Generate icons and build the launcher

```sh
# Generate icons (one-off, output committed to static/icons/)
uv run --with pillow python scripts/make_icons.py

# Build ~/Applications/Writing Assistant.app
bash scripts/build_launcher.sh
```

### Step 2 — Pin to Dock

Drag `~/Applications/Writing Assistant.app` to the Dock.

From now on: click the Dock icon → native window opens (2–4 s cold start). Close the window →
server exits immediately.

### Logs

```sh
tail -f ~/Library/Logs/writing-assistant.log
```

### Stop the server manually

Press **⌘Q** in the app window, or close the window.

---

## Troubleshooting

### App shows "claude CLI not found"

The server can't find the `claude` binary on the PATH the launcher uses. Check:

```sh
# Confirm claude is on PATH
command -v claude

# Confirm it's authenticated (must succeed interactively before the launcher can use it)
claude --version
```

If `claude` is installed but not found, add its directory to the `PATH` line in
`scripts/launcher.applescript` and rebuild: `bash scripts/build_launcher.sh`.

### App shows "claude CLI failed" after a reboot

The CLI's subscription auth (OAuth/keychain) may need to be re-confirmed. Run `claude` once
interactively in a terminal to re-authenticate, then try the launcher again.

### Request takes more than 120 seconds

The server returns a 504 with a clear message. This can happen under heavy subscription load.
Try again; if it happens consistently, check your Claude subscription status.

### Launcher opens but window shows a connection error

The server crashed on startup. Check the log:

```sh
tail -30 ~/Library/Logs/writing-assistant.log
```

Or run the app directly in a terminal to see the error inline:

```sh
uv run python -m assistant.desktop
```

---

## Development

```sh
# Run tests
uv run pytest -v

# Lint and type-check
uv run ruff check assistant/
uv run ruff format --check assistant/
uv run mypy assistant/
```

---

## Style guidelines

The global and per-channel style rules live in plain-text files you can edit without touching code:

- `assistant/prompts/polish.txt` — the 4-step pipeline + global rules
- `assistant/prompts/channels/*.txt` — per-channel formatting rules

Edit these files and the next request picks up the changes immediately; no restart needed.

---

## Model routing

Short text (under 60 words) that looks like English gets routed to Haiku (faster, cheaper quota);
everything else goes to Sonnet. The model name is shown in the "Polished Text" card header.

To update the Sonnet model ID (e.g. when a newer version is available to your CLI):

```python
# assistant/routing.py
SONNET_MODEL = "claude-sonnet-5"  # update here
```
