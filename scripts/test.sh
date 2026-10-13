#!/usr/bin/env bash
# Runs the Swift test suite. With only Command Line Tools installed (no Xcode),
# SwiftPM doesn't find Swift Testing on its own, so pass its framework paths explicitly.
set -euo pipefail

CLT="$(xcode-select -p)"
FRAMEWORKS="$CLT/Library/Developer/Frameworks"
LIBS="$CLT/Library/Developer/usr/lib"

exec swift test \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$LIBS" \
  "$@"
