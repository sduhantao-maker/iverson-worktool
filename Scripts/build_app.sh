#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIN_MACOS="13.0"
ARCHS=(arm64 x86_64)
BUILD_ROOT="$(/usr/bin/mktemp -d /tmp/KeepGoing-build.XXXXXX)"
trap '/bin/rm -rf "$BUILD_ROOT"' EXIT
APP="$BUILD_ROOT/Iverson’s WorkTool.app"
FINAL_APP="$ROOT/dist/Iverson’s WorkTool.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

APP_SOURCES=(
  main.swift
  Shell.swift
  Palette.swift
  GlassControls.swift
  UIComponents.swift
  KeepGoingPower.swift
  KeepGoingViewController.swift
  AutoMessageSettings.swift
  AutoMessageMessageComposer.swift
  AutoMessageRunner.swift
  AutoMessageViewController.swift
  RootViewController.swift
  App.swift
)

HELPER_SOURCES=(
  Shell.swift
  AutoMessageSettings.swift
  AutoMessageMessageComposer.swift
  AutoMessageRunner.swift
  automessage_helper.swift
)

# compile <output> <source...>: one slice per architecture, joined into a universal binary.
# The explicit -target pins the minimum macOS; without it swiftc uses the build machine's.
compile() {
  local output="$1"
  shift
  local sources=()
  local source
  for source in "$@"; do
    sources+=("$ROOT/Sources/$source")
  done
  local slices=()
  local arch
  for arch in $ARCHS; do
    local slice="$BUILD_ROOT/${output:t}.$arch"
    /usr/bin/xcrun swiftc \
      -O \
      -target "$arch-apple-macos$MIN_MACOS" \
      -framework Cocoa \
      -framework IOKit \
      -o "$slice" \
      "${sources[@]}"
    slices+=("$slice")
  done
  /usr/bin/lipo -create -output "$output" "${slices[@]}"
}

/bin/rm -rf "$FINAL_APP" "$ROOT/dist/KeepGoing.app" "$ROOT/dist/keepgoing.app"
/bin/mkdir -p "$MACOS" "$RESOURCES"

/bin/cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
/bin/cp "$ROOT/Resources/keepgoing-helper" "$RESOURCES/keepgoing-helper"
/bin/cp "$ROOT/Resources/install-helper.sh" "$RESOURCES/install-helper.sh"
/bin/cp "$ROOT/Resources/uninstall-helper.sh" "$RESOURCES/uninstall-helper.sh"
/bin/chmod 755 "$RESOURCES/keepgoing-helper" "$RESOURCES/install-helper.sh" "$RESOURCES/uninstall-helper.sh"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  /bin/cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
  /usr/bin/python3 "$ROOT/Scripts/make_icon.py" "$RESOURCES/AppIcon.icns"
fi

compile "$MACOS/KeepGoing" "${APP_SOURCES[@]}"
compile "$RESOURCES/keepgoing-automessage" "${HELPER_SOURCES[@]}"
/bin/chmod 755 "$RESOURCES/keepgoing-automessage"

/usr/bin/xattr -cr "$APP" || true
/usr/bin/xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
# Sign the nested helper first, then the app around it.
/usr/bin/codesign --force --sign - --identifier com.iverson.keepgoing.automessage "$RESOURCES/keepgoing-automessage"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

/bin/mkdir -p "$ROOT/dist"
/usr/bin/ditto --noextattr --norsrc "$APP" "$FINAL_APP"
/usr/bin/xattr -d com.apple.FinderInfo "$FINAL_APP" 2>/dev/null || true

echo "$FINAL_APP"
