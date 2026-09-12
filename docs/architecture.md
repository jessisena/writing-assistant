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

A pure function (`routing.py`) routes to Haiku for short, confidently-English input and to Sonnet
for everything else. A Haiku triage call would have been the obvious "intelligent routing" design
but adds a full round-trip to every request to save quota on some of them. The local heuristic gets
the same result for free.

### Synchronous POST, not background-task + polling

A background-task + polling design has a known failure mode: without a failed state, a timeout
leaves the UI on "running" forever. A single ~10–30s call fits a plain POST with a spinner and
returns real HTTP status codes on failure.

### `learning_summary` gate — enforced server-side

When input was not in English (`was_translated: true`), the learning summary is always `null`. This
is enforced in **two** places: the prompt instructs it, and `pipeline.py` strips any summary that
comes back anyway. The prompt instruction alone is not a guarantee; the server layer is the actual
invariant. `learning_summary is not None` implies `was_translated is False`.

### No build step

The frontend is vanilla HTML/JS/CSS served by FastAPI's `StaticFiles`. The server serves the UI
immediately on start with no risk of a stale or missing `dist/` directory.

### CLI subprocess auth

Calls go through the `claude` CLI with subscription OAuth (no `ANTHROPIC_API_KEY`). The binary is
resolved to an absolute path at import time via `shutil.which` so the launcher's minimal `PATH`
does not cause a `FileNotFoundError`.

### On-demand launch + auto-shutdown

The app is not always-on. An AppleScript `.app` (`scripts/launcher.applescript`) runs
`uv run python -m assistant.desktop`, which starts uvicorn in a background thread and opens a
native macOS WKWebView window — server and UI in one process. When the window closes,
`desktop.py`'s `on_closed` handler sets `server.should_exit = True`, stopping the server
immediately.

The frontend also sends a heartbeat `POST /api/heartbeat` every 15 seconds. `assistant/session.py`
watches for the heartbeat to go stale and raises `SIGTERM` after 120 seconds of silence — a
fallback that matters only for the standalone `uv run uvicorn …` dev workflow, where there is no
`on_closed` hook. `watch()` does nothing until the first heartbeat arrives, so the dev server never
auto-exits on startup.

---

## Request flow

```
paste + channel
      │
      ▼  POST /api/polish
┌────────────────────────────────────────┐
│ pick_model(text)   ← pure function     │
│   ≤60 words + confident English → Haiku│
│   everything else             → Sonnet │
└────────────────────────────────────────┘
      │
      ▼  one run_claude() call
         MAX_THINKING_TOKENS=0, MCP disabled
┌────────────────────────────────────────┐
│ polish.txt  (4 steps)                  │
│  1. detect language                    │
│       not English → translate          │
│       English     → skip              │
│  2. apply global style guidelines      │
│  3. apply {{CHANNEL_GUIDELINES}}       │
│  4. emit JSON                          │
└────────────────────────────────────────┘
      │  extract_json()  (tolerant of preamble/fences)
      ▼
{polished_text, learning_summary|null,
 detected_language, was_translated, model_used}
```

---

## File layout

```
assistant/
  claude_cli.py      run_claude() + extract_json()
  desktop.py         desktop entry point: starts uvicorn in thread, opens pywebview window
  models.py          Channel enum, request/response Pydantic models
  routing.py         pick_model() heuristic + model ID constants
  pipeline.py        polish() — the single entry point per request
  session.py         heartbeat watcher — auto-SIGTERM for standalone dev server
  main.py            FastAPI: /api/health, /api/polish, /api/heartbeat, StaticFiles mount
  prompts/
    polish.txt       4-step instructions + global style rules (editable)
    channels/        per-channel rules — one .txt per channel (editable)
static/
  index.html  app.js  styles.css
  icons/           icon-192.png, icon-512.png, icon-1024.png, icon.icns
scripts/
  serve.sh         dev-only: idempotent server start + readiness probe
  stop.sh          kill uvicorn by port
  build_launcher.sh  osacompile → ~/Applications/Writing Assistant.app
  launcher.applescript
  make_icons.py    generate icons (run once via uv run --with pillow)
tests/
  test_pipeline.py   (22 tests)
  test_routing.py    (11 tests)
  test_routes.py     (16 tests)
```

---

## Error mapping

| Failure | HTTP |
|---|---|
| `claude` binary not found | 503 |
| CLI exits non-zero | 502 |
| `subprocess.TimeoutExpired` | 504 |
| Unparsable JSON / schema mismatch | 502 |
| Empty input | 422 |

---

## Model IDs

Defined as constants in `assistant/routing.py`:

- `HAIKU_MODEL = "claude-haiku-4-5-20251001"`
- `SONNET_MODEL = "claude-sonnet-4-6"`

Update `SONNET_MODEL` here when a newer Sonnet becomes available to the CLI.
