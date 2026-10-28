#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFTC="${SWIFTC:-swiftc}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$SWIFTC" -swift-version 5 Sources/UsageParsing.swift Sources/Strings.swift Sources/MonthLabels.swift Tests/main.swift -o "$TMP/tests"
"$TMP/tests"
"$SWIFTC" -swift-version 5 Sources/Strings.swift Sources/AgentUsage.swift Sources/AgentCatalog.swift Sources/AgentSources.swift Tests/AgentUsageTests.swift -o "$TMP/agent-tests"
"$TMP/agent-tests"
"$SWIFTC" -swift-version 5 Sources/UsagePreferences.swift Sources/AgentAutomaticModels.swift Tests/AutomaticTests.swift -o "$TMP/automatic-tests"
"$TMP/automatic-tests"
