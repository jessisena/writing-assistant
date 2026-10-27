#!/usr/bin/env bash
# Builds Writing Assistant.app from the Swift package, ad-hoc signs it, and installs it.
# Usage: scripts/build_app.sh   (set INSTALL_DIR to install somewhere other than ~/Applications)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Writing Assistant.app"
EXECUTABLE="WritingAssistant"
RESOURCE_BUNDLE="WritingAssistant_WritingAssistantCore.bundle"
BUILD_DIR="$REPO_DIR/build"
APP="$BUILD_DIR/$APP_NAME"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found. $2"
}

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

mkdir -p "$INSTALL_DIR"
INSTALLED="$INSTALL_DIR/$APP_NAME"
if [[ -e "$INSTALLED" ]]; then
  echo "Moving the previous $INSTALLED to the Trash"
  trash "$INSTALLED"
fi
ditto "$APP" "$INSTALLED"

echo "Installed: $INSTALLED"
echo "Drag it to the Dock to pin it."
