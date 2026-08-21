#!/bin/bash
# Build TokensBar.app (unsigned, ad-hoc signed) from Sources/main.swift
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/TokensBar.app"
ARCH="$(uname -m)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"

swiftc \
  -O \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -framework AppKit \
  -o "$APP/Contents/MacOS/TokensBar" \
  "$DIR/Sources/main.swift"

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warn: ad-hoc codesign failed (app still runs)"

echo "built: $APP"
