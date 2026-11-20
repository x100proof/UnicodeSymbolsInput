#!/usr/bin/env bash
# Build Unicode Symbols Input with the Swift compiler alone (no Xcode project).
#
#   ./build.sh              run the tests, then build build/UnicodeSymbolsInput.app and build/usi-ctl
#   ./build.sh test         run the tests only
#   UNIVERSAL=1 ./build.sh  build for both Apple silicon and Intel (used by package.sh)
#
# Needs the Xcode Command Line Tools (`xcode-select --install`). BUILD_DIR
# overrides the output directory (default: ./build). usi-ctl is also copied
# into the app bundle (Contents/MacOS/usi-ctl) so an installed copy can
# register itself. The bundle is ad-hoc signed; package.sh can re-sign it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="${BUILD_DIR:-$HERE/build}"
APP="$BUILD/UnicodeSymbolsInput.app"
VERSION="$(cat "$HERE/VERSION")"
NATIVE="$(uname -m)"
if [ -n "${UNIVERSAL:-}" ]; then ARCHS=(arm64 x86_64); else ARCHS=("$NATIVE"); fi

swiftc_for() {  # swiftc_for ARCH ARGS...
  local arch="$1"; shift
  swiftc -O -swift-version 5 -target "$arch-apple-macos12.0" \
    -module-cache-path "$BUILD/module-cache/$arch" "$@"
}

# compile OUT ARGS...: build OUT for every arch in ARCHS, joined with lipo if more than one.
compile() {
  local out="$1"; shift
  if [ ${#ARCHS[@]} -eq 1 ]; then
    swiftc_for "${ARCHS[0]}" "$@" -o "$out"
    return
  fi
  local slices=() arch
  for arch in "${ARCHS[@]}"; do
    mkdir -p "$BUILD/arch/$arch"
    swiftc_for "$arch" "$@" -o "$BUILD/arch/$arch/$(basename "$out")"
    slices+=("$BUILD/arch/$arch/$(basename "$out")")
  done
  lipo -create "${slices[@]}" -output "$out"
}

mkdir -p "$BUILD"
cd "$HERE"

echo "==> Testing"
swiftc_for "$NATIVE" -module-name Tests Sources/Core/*.swift Tests/*.swift -o "$BUILD/tests"
"$BUILD/tests" "$HERE/Sets"
[ "${1:-}" = test ] && exit 0

echo "==> Building $APP (${ARCHS[*]})"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sets"
compile "$APP/Contents/MacOS/UnicodeSymbolsInput" -module-name UnicodeSymbolsInput \
  -framework InputMethodKit Sources/Core/*.swift Sources/App/*.swift
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/icon.tiff "$APP/Contents/Resources/"
# The catalog, every set (so the input menu can switch between them) and their licences.
(cd Sets && find . -name '*.json' -o -path './licenses/*' -type f) | while read -r f; do
  mkdir -p "$APP/Contents/Resources/Sets/$(dirname "$f")"
  cp "Sets/$f" "$APP/Contents/Resources/Sets/$f"
done

echo "==> Building usi-ctl"
compile "$BUILD/usi-ctl" -module-name usictl -framework Carbon \
  Sources/Core/*.swift Sources/Tools/usi-ctl/main.swift
cp "$BUILD/usi-ctl" "$APP/Contents/MacOS/usi-ctl"

# Sign the helper first, then the bundle (which seals it).
codesign --force --sign - "$APP/Contents/MacOS/usi-ctl"
codesign --force --sign - "$APP"

echo "Built $APP ($VERSION, ${ARCHS[*]})"
