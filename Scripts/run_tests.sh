#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BINARY="$(/usr/bin/mktemp /tmp/WorkToolTests.XXXXXX)"
trap '/bin/rm -f "$TEST_BINARY"' EXIT

/usr/bin/xcrun swiftc \
  -framework Cocoa \
  -framework IOKit \
  "$ROOT/Sources/Shell.swift" \
  "$ROOT/Sources/AutoMessageSettings.swift" \
  "$ROOT/Sources/AutoMessageMessageComposer.swift" \
  "$ROOT/Sources/AutoMessageRunner.swift" \
  "$ROOT/Sources/KeepGoingPower.swift" \
  "$ROOT/Tests/TestSupport.swift" \
  "$ROOT/Tests/AutoMessageMessageComposerTests.swift" \
  "$ROOT/Tests/AutoMessageRunnerTests.swift" \
  "$ROOT/Tests/KeepGoingGuardTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

/bin/zsh "$ROOT/Tests/keepgoing_helper_tests.sh" "$ROOT/Resources/keepgoing-helper"

echo "Tests passed"
