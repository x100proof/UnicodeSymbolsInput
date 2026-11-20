#!/usr/bin/env bash
# Build Unicode Symbols Input with the Swift compiler alone (no Xcode project).
#
#   ./build.sh          run the tests, then build build/UnicodeSymbolsInput.app and build/usi-ctl
#   ./build.sh test     run the tests only
#
# Needs the Xcode Command Line Tools (`xcode-select --install`). BUILD_DIR
# overrides the output directory (default: ./build).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="${BUILD_DIR:-$HERE/build}"
APP="$BUILD/UnicodeSymbolsInput.app"
VERSION="$(cat "$HERE/VERSION")"
TARGET="$(uname -m)-apple-macos12.0"
SWIFTC=(swiftc -O -swift-version 5 -target "$TARGET" -module-cache-path "$BUILD/module-cache")

mkdir -p "$BUILD"
cd "$HERE"

echo "==> Testing"
"${SWIFTC[@]}" -module-name Tests Sources/Core/*.swift Tests/*.swift -o "$BUILD/tests"
"$BUILD/tests" "$HERE/Sets"
[ "${1:-}" = test ] && exit 0

echo "==> Building $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sets"
"${SWIFTC[@]}" -module-name UnicodeSymbolsInput -framework InputMethodKit \
  Sources/Core/*.swift Sources/App/*.swift -o "$APP/Contents/MacOS/UnicodeSymbolsInput"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/icon.tiff "$APP/Contents/Resources/"
# The catalog, every set (so the input menu can switch between them) and their licences.
(cd Sets && find . -name '*.json' -o -path './licenses/*' -type f) | while read -r f; do
  mkdir -p "$APP/Contents/Resources/Sets/$(dirname "$f")"
  cp "Sets/$f" "$APP/Contents/Resources/Sets/$f"
done
codesign --force --sign - "$APP"

echo "==> Building $BUILD/usi-ctl"
"${SWIFTC[@]}" -module-name usictl -framework Carbon \
  Sources/Core/*.swift Sources/Tools/usi-ctl/main.swift -o "$BUILD/usi-ctl"

echo "Built $APP ($VERSION)"
