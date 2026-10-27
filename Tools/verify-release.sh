#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="TokensBar.app"
BIN="$APP/Contents/MacOS/TokensBar"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$VERSION" ]]; then
  echo "Tag $RELEASE_TAG does not match bundle version $VERSION" >&2
  exit 1
fi
plutil -lint "$APP/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "ci.tokens.menubar"
test -s "$APP/Contents/Resources/AppIcon.icns"
test -x "$BIN"
lipo "$BIN" -verify_arch arm64 x86_64
lipo -archs "$BIN"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1
