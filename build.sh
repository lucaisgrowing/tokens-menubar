#!/bin/bash
# Build TokensBar.app (unsigned, ad-hoc signed) from Sources/main.swift
#
#   ./build.sh              build for this Mac's architecture
#   ./build.sh --universal  build a universal (arm64 + x86_64) binary
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/TokensBar.app"
BIN="$APP/Contents/MacOS/TokensBar"
SRC="$DIR/Sources/main.swift"
DEPLOY_TARGET="13.0"

UNIVERSAL=0
[[ "${1:-}" == "--universal" ]] && UNIVERSAL=1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"

compile() { # $1 = arch, $2 = output path
  swiftc -O -swift-version 5 \
    -target "$1-apple-macos$DEPLOY_TARGET" \
    -framework AppKit \
    -o "$2" "$SRC"
}

if [[ $UNIVERSAL -eq 1 ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  compile arm64 "$TMP/TokensBar-arm64"
  compile x86_64 "$TMP/TokensBar-x86_64"
  lipo -create -output "$BIN" "$TMP/TokensBar-arm64" "$TMP/TokensBar-x86_64"
else
  compile "$(uname -m)" "$BIN"
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warn: ad-hoc codesign failed (app still runs)"

echo "built: $APP"
lipo -archs "$BIN" | sed 's/^/  archs: /'
