#!/usr/bin/env bash
# Build a distributable installer: build/UnicodeSymbolsInput-<version>.pkg
#
#   ./package.sh
#
# The package holds a universal (Apple silicon + Intel) build, installs it into
# /Library/Input Methods for all users (administrator password required), and
# its postinstall script registers and enables it for the logged-in user.
#
# Signing is optional and off by default. Set any of these to turn it on:
#   APP_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#       codesign the app (hardened runtime, secure timestamp)
#   INSTALLER_SIGN_IDENTITY="Developer ID Installer: Name (TEAMID)"
#       sign the .pkg
#   NOTARY_PROFILE=<keychain profile from `xcrun notarytool store-credentials`>
#       notarize the signed .pkg with Apple and staple the ticket
# Without them the app is ad-hoc signed and the .pkg is unsigned: macOS will
# block it until the user allows it in System Settings > Privacy & Security.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="${BUILD_DIR:-$HERE/build}"
VERSION="$(cat "$HERE/VERSION")"
ID=org.100proof.pkg.UnicodeSymbolsInput
APP_NAME=UnicodeSymbolsInput.app
ROOT="$BUILD/pkg/root"
SCRIPTS="$BUILD/pkg/scripts"
COMPONENTS="$BUILD/pkg/components"
OUT="$BUILD/UnicodeSymbolsInput-$VERSION.pkg"

if [ -n "${NOTARY_PROFILE:-}" ] && [ -z "${INSTALLER_SIGN_IDENTITY:-}" ]; then
  echo "NOTARY_PROFILE needs INSTALLER_SIGN_IDENTITY too: Apple only notarizes signed packages." >&2
  exit 2
fi
if [ -n "${INSTALLER_SIGN_IDENTITY:-}" ] && [ -z "${APP_SIGN_IDENTITY:-}" ]; then
  echo "warning: INSTALLER_SIGN_IDENTITY without APP_SIGN_IDENTITY: notarization will reject the ad-hoc signed app." >&2
fi

UNIVERSAL=1 BUILD_DIR="$BUILD" "$HERE/build.sh"

echo "==> Staging the payload"
rm -rf "$BUILD/pkg"
mkdir -p "$ROOT/Library/Input Methods" "$SCRIPTS" "$COMPONENTS"
ditto "$BUILD/$APP_NAME" "$ROOT/Library/Input Methods/$APP_NAME"
APP="$ROOT/Library/Input Methods/$APP_NAME"
# Drop extended attributes such as quarantine so they aren't packaged. macOS's
# protected com.apple.provenance can't be removed; pkgbuild lists it as "._*"
# entries in the payload, which Installer restores as attributes, not files.
xattr -cr "$ROOT" 2>/dev/null || true

if [ -n "${APP_SIGN_IDENTITY:-}" ]; then
  echo "==> Signing the app as $APP_SIGN_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP/Contents/MacOS/usi-ctl"
  codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

cp "$HERE/Resources/pkg/scripts/postinstall" "$SCRIPTS/postinstall"
chmod 755 "$SCRIPTS/postinstall"

# Install exactly where we say: by default pkgbuild marks bundles relocatable,
# and Installer would then "update" any other copy with the same bundle id it
# finds (a build directory, a per-user install) instead of /Library/Input Methods.
pkgbuild --analyze --root "$ROOT" "$BUILD/pkg/components.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$BUILD/pkg/components.plist"

echo "==> Building the component package"
pkgbuild --root "$ROOT" --component-plist "$BUILD/pkg/components.plist" \
  --identifier "$ID" --version "$VERSION" --install-location / \
  --scripts "$SCRIPTS" "$COMPONENTS/UnicodeSymbolsInput-component.pkg"

echo "==> Building $OUT"
sed "s/__VERSION__/$VERSION/g" "$HERE/Resources/pkg/distribution.xml" > "$BUILD/pkg/distribution.xml"
SIGN=()
[ -n "${INSTALLER_SIGN_IDENTITY:-}" ] && SIGN=(--sign "$INSTALLER_SIGN_IDENTITY" --timestamp)
rm -f "$OUT"
productbuild --distribution "$BUILD/pkg/distribution.xml" --package-path "$COMPONENTS" \
  ${SIGN[@]+"${SIGN[@]}"} "$OUT"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "==> Notarizing (this can take a few minutes)"
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT"
fi

echo
echo "Built $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '))"
if [ -z "${INSTALLER_SIGN_IDENTITY:-}" ]; then
  cat <<'EOF'

WARNING: this package is UNSIGNED (and the app only ad-hoc signed). macOS will
refuse to open it at first. Each user has to try to open it once, then go to
System Settings > Privacy & Security, click "Open Anyway" next to the message
about UnicodeSymbolsInput, and confirm. To ship a package that opens normally,
set APP_SIGN_IDENTITY, INSTALLER_SIGN_IDENTITY and NOTARY_PROFILE (see the top
of package.sh).
EOF
fi
