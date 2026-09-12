#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8765}"
PIDS=$(lsof -ti tcp:"${PORT}" 2>/dev/null || true)
if [[ -z "$PIDS" ]]; then
  echo "Writing Assistant: server is not running."
  exit 0
fi
echo "$PIDS" | xargs kill
echo "Writing Assistant: server stopped."
