#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8765}"
LOG="${LOG:-$HOME/Library/Logs/writing-assistant.log}"
URL="http://127.0.0.1:${PORT}"

# Resolve uv — needed because AppleScript's do shell script runs with a minimal PATH.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

UV="$(command -v uv 2>/dev/null || true)"
if [[ -z "$UV" ]]; then
  echo "ERROR: uv not found on PATH. Install it from https://docs.astral.sh/uv/ and ensure its directory is on your PATH." >&2
  exit 1
fi

# Probe: treat any HTTP response as "server is up".
# /api/health returns 503 when claude CLI is missing — that is still a running server.
probe() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "${URL}/api/health" 2>/dev/null || true)
  [[ "$code" =~ ^[0-9]{3}$ ]]
}

if probe; then
  exit 0
fi

cd "$REPO_DIR"
nohup "$UV" run uvicorn assistant.main:app \
  --host 127.0.0.1 --port "${PORT}" \
  >>"$LOG" 2>&1 </dev/null &

# Wait for the server to be ready (up to ~20s)
for _ in $(seq 1 80); do
  sleep 0.25
  if probe; then
    # Print the HTTP status code so the AppleScript caller can check for 503
    curl -s -o /dev/null -w '%{http_code}' --max-time 2 "${URL}/api/health" || true
    exit 0
  fi
done

echo "ERROR: server did not start within 20 seconds" >&2
exit 1
