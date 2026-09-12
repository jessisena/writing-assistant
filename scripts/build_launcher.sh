#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_DIR/scripts/launcher.applescript"
APP="$HOME/Applications/Writing Assistant.app"
ICON="$REPO_DIR/static/icons/icon.icns"

echo "Building launcher at: $APP"

# Inject the absolute repo path into a temp copy of the AppleScript source,
# so the committed source stays machine-independent.
TMP_SCRIPT="$(mktemp /tmp/launcher.XXXXXX.applescript)"
trap 'rm -f "$TMP_SCRIPT"' EXIT
sed "s|__PROJECT_DIR__|$REPO_DIR|g" "$SCRIPT" > "$TMP_SCRIPT"

osacompile -o "$APP" "$TMP_SCRIPT"

if [[ -f "$ICON" ]]; then
  cp "$ICON" "$APP/Contents/Resources/applet.icns"
  # Touch so Finder reloads the icon from disk
  touch "$APP"
  echo "Icon installed."
else
  echo "Warning: $ICON not found — run 'uv run --with pillow python scripts/make_icons.py' first."
fi

echo "Done. Drag '$APP' to the Dock to pin it."
