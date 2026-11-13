#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
xcrun swiftc -swift-version 5 -warnings-as-errors \
    TVZPrefs/TVZTouchVizSelection.swift tests/selection_test.swift -o "$TMP/selection-test"
"$TMP/selection-test"
