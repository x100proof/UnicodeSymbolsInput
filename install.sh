#!/usr/bin/env bash
# Build and install Unicode Symbols Input for the current user.
#
#   ./install.sh                          build, install, keep your current set choices
#   ./install.sh --prover agda            …and use Agda as the Prover set
#   ./install.sh --prover lean4 --emoji none
#   ./install.sh --uninstall              remove it again
#
# Any `--<class> <set|none>` pair chooses that class's set (see `build/usi-ctl
# status` for the classes and sets). Choices are kept across reinstalls and can
# also be changed from the input menu or with `build/usi-ctl use <class> <set>`.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="${BUILD_DIR:-$HERE/build}"
NAME=UnicodeSymbolsInput
DEST="$HOME/Library/Input Methods/$NAME.app"
CTL="$BUILD/usi-ctl"
USAGE="usage: $0 [--prover lean4|agda|none] [--emoji gemoji|none] | --uninstall"

CHOICES=()
UNINSTALL=
while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) UNINSTALL=1 ;;
    -h|--help) echo "$USAGE"; exit 0 ;;
    --*=*) CHOICES+=("${1%%=*}" "${1#*=}") ;;
    --*) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; CHOICES+=("$1" "$2"); shift ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
  shift
done

if [ -n "$UNINSTALL" ]; then
  [ -x "$CTL" ] && "$CTL" unregister || true
  pkill -x "$NAME" 2>/dev/null || true
  rm -rf "$DEST"
  echo "Removed $DEST. Your set choices are kept in the preferences domain"
  echo "org.100proof.inputmethod.UnicodeSymbolsInput (\`defaults delete\` it to forget them)."
  exit 0
fi

BUILD_DIR="$BUILD" "$HERE/build.sh"

echo "==> Installing to $DEST"
pkill -x "$NAME" 2>/dev/null || true   # the running copy would keep the old code
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
ditto "$BUILD/$NAME.app" "$DEST"
"$CTL" register "$DEST"

i=0
while [ $i -lt ${#CHOICES[@]} ]; do
  "$CTL" use "${CHOICES[$i]#--}" "${CHOICES[$((i + 1))]}"
  i=$((i + 2))
done

echo
"$CTL" status
cat <<EOF

Done. Pick "Unicode Symbols" from the input menu in the menu bar (or run
\`$CTL select\`), then type \\to, \\all or \\:smile: in any app.
If it isn't in the input menu, log out and back in once.
EOF
