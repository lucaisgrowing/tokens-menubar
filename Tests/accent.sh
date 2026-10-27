#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -swift-version 5 -framework AppKit Sources/Appearance.swift Tests/Accent/main.swift -o "$TMP/accent-test"
"$TMP/accent-test"
