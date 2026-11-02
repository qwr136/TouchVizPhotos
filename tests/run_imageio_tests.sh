#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo 'ImageIO requires macOS' >&2; exit 2; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -x objective-c++ \
  TVZPrefs/TVZTouchVizImageFrames.mm tests/imageio_test.mm \
  -framework ImageIO -framework CoreFoundation -framework CoreGraphics -o "$TMP/imageio-test"
"$TMP/imageio-test" "$PWD/tests/fixtures"
