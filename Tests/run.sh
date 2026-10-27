#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFTC="${SWIFTC:-swiftc}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$SWIFTC" -swift-version 5 Sources/UsageParsing.swift Sources/Strings.swift Tests/main.swift -o "$TMP/tests"
"$TMP/tests"
