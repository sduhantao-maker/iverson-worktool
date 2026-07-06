#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$(/usr/bin/mktemp -d /tmp/KeepGoing-build.XXXXXX)"
trap '/bin/rm -rf "$BUILD_ROOT"' EXIT
APP="$BUILD_ROOT/KeepGoing.app"
FINAL_APP="$ROOT/dist/KeepGoing.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

/bin/rm -rf "$FINAL_APP" "$ROOT/dist/keepgoing.app"
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

/usr/bin/swiftc \
  -O \
  -framework Cocoa \
  -o "$MACOS/KeepGoing" \
  "$ROOT/Sources/main.swift" \
  "$ROOT/Sources/UIComponents.swift" \
  "$ROOT/Sources/KeepGoingViewController.swift" \
  "$ROOT/Sources/App.swift"

/usr/bin/xattr -cr "$APP" || true
/usr/bin/xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

/bin/mkdir -p "$ROOT/dist"
/usr/bin/ditto --noextattr --norsrc "$APP" "$FINAL_APP"
/usr/bin/xattr -d com.apple.FinderInfo "$FINAL_APP" 2>/dev/null || true

echo "$FINAL_APP"
