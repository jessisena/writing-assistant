#!/usr/bin/env bash
# Runs the Swift test suite. With only Command Line Tools installed (no Xcode),
# SwiftPM doesn't find Swift Testing on its own, so pass its framework paths explicitly.
# With Xcode (as in CI) those paths don't exist and plain `swift test` works.
set -euo pipefail

DEVELOPER_DIR_PATH="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
LIBS="$DEVELOPER_DIR_PATH/Library/Developer/usr/lib"

if [[ ! -d "$FRAMEWORKS/Testing.framework" ]]; then
  exec swift test "$@"
fi

exec swift test \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$LIBS" \
  "$@"
