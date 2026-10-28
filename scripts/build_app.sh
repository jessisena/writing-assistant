#!/usr/bin/env bash
# Builds Writing Assistant.app from the Swift package, ad-hoc signs it, and installs it.
# Usage: scripts/build_app.sh [--relaunch]
#   --relaunch  quit the running app before installing and open the new build afterwards
# Set INSTALL_DIR to install somewhere other than ~/Applications.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Writing Assistant.app"
EXECUTABLE="WritingAssistant"
RESOURCE_BUNDLE="WritingAssistant_WritingAssistantCore.bundle"
BUILD_DIR="$REPO_DIR/build"
APP="$BUILD_DIR/$APP_NAME"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
BUNDLE_ID="local.writing-assistant"
QUIT_TIMEOUT_SECONDS=10

fail() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found. $2"
}

app_is_running() {
  [[ "$(osascript -e "application id \"$BUNDLE_ID\" is running")" == "true" ]]
}

quit_running_app() {
  app_is_running || return 0
  echo "Quitting the running Writing Assistant..."
  osascript -e "tell application id \"$BUNDLE_ID\" to quit"
  local waited=0
  while app_is_running; do
    ((waited < QUIT_TIMEOUT_SECONDS)) ||
      fail "Writing Assistant did not quit within ${QUIT_TIMEOUT_SECONDS}s. Quit it and rerun."
    sleep 1
    waited=$((waited + 1))
  done
}

RELAUNCH=false
for arg in "$@"; do
  case "$arg" in
  --relaunch) RELAUNCH=true ;;
  *) fail "unknown argument: $arg (usage: scripts/build_app.sh [--relaunch])" ;;
  esac
done

require_tool swift "Install the Command Line Tools with: xcode-select --install"
require_tool trash "Install it with: brew install trash"

cd "$REPO_DIR"

echo "Building release binary..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

[[ -x "$BIN_DIR/$EXECUTABLE" ]] || fail "missing $BIN_DIR/$EXECUTABLE after build"
[[ -d "$BIN_DIR/$RESOURCE_BUNDLE" ]] || fail "missing $BIN_DIR/$RESOURCE_BUNDLE after build"

echo "Assembling $APP"
if [[ -e "$APP" ]]; then
  trash "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$REPO_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$REPO_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# The .app root can't hold extra files (codesign rejects unsealed root contents),
# so the SwiftPM resource bundle goes in Contents/Resources.
ditto "$BIN_DIR/$RESOURCE_BUNDLE" "$APP/Contents/Resources/$RESOURCE_BUNDLE"
PROMPT_CHECK="$APP/Contents/Resources/$RESOURCE_BUNDLE/Prompts/polish.txt"
[[ -f "$PROMPT_CHECK" ]] || fail "bundled prompts missing from the app: $PROMPT_CHECK"

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

if [[ "$RELAUNCH" == true ]]; then
  quit_running_app
fi

mkdir -p "$INSTALL_DIR"
INSTALLED="$INSTALL_DIR/$APP_NAME"
if [[ -e "$INSTALLED" ]]; then
  echo "Moving the previous $INSTALLED to the Trash"
  trash "$INSTALLED"
fi
ditto "$APP" "$INSTALLED"

echo "Installed: $INSTALLED"

echo "Refreshing the Services menu..."
if ! /System/Library/CoreServices/pbs -update; then
  echo "warning: pbs -update failed, so \"Polish with Writing Assistant\" may not appear in" \
    "the Services menu until you log out and back in." >&2
fi

if [[ "$RELAUNCH" == true ]]; then
  echo "Opening $INSTALLED"
  open "$INSTALLED"
fi

echo "Drag it to the Dock to pin it."
echo "To polish selected text from any app, use Services → Polish with Writing Assistant." \
  "Assign a shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services."
