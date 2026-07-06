#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BINARY="$(/usr/bin/mktemp /tmp/AutoMessageMessageComposerTests.XXXXXX)"
trap '/bin/rm -f "$TEST_BINARY"' EXIT

/usr/bin/swiftc \
  "$ROOT/Sources/AutoMessageSettings.swift" \
  "$ROOT/Sources/AutoMessageMessageComposer.swift" \
  "$ROOT/Tests/AutoMessageMessageComposerTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

echo "Tests passed"
