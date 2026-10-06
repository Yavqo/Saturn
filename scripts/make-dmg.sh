#!/bin/bash
# Build the Saturn installer disk image.
#   scripts/make-dmg.sh path/to/Saturn.app dist/Saturn-0.1.0.dmg
# Uses `create-dmg` (brew install create-dmg) for the branded window; if that is missing or Finder
# scripting isn't allowed, it falls back to a plain disk image with an Applications shortcut.
set -euo pipefail
APP="${1:?usage: make-dmg.sh <Saturn.app> <output.dmg>}"
OUT="${2:?usage: make-dmg.sh <Saturn.app> <output.dmg>}"
cd "$(dirname "$0")/.."
rm -f "$OUT"; mkdir -p "$(dirname "$OUT")"

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Saturn.app"

BG="$(mktemp -d)/background.png"
HAVE_BG=0
python3 scripts/dmg_background.py "$BG" 2>/dev/null && HAVE_BG=1 || echo "    (no Pillow: building without a background image)"

styled() {
  local args=(--volname "Saturn" --volicon resources/Saturn.icns --window-pos 200 120 --window-size 660 400
              --icon-size 120 --icon "Saturn.app" 180 200 --hide-extension "Saturn.app" --app-drop-link 480 200 --no-internet-enable "$@")
  [ "$HAVE_BG" = 1 ] && args+=(--background "$BG")
  create-dmg "${args[@]}" "$OUT" "$STAGE" > /dev/null
}

if command -v create-dmg > /dev/null; then
  # Finder scripting can hang on a permission prompt, so give it a minute, then fall back.
  styled & PID=$!
  for _ in $(seq 1 60); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
  if kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null || true; pkill -f create-dmg 2>/dev/null || true; echo "    (styled window timed out)"; fi
  wait "$PID" 2>/dev/null || true
  hdiutil detach /Volumes/Saturn -force > /dev/null 2>&1 || true
fi

if [ ! -s "$OUT" ]; then
  echo "    (building a plain disk image)"
  PLAIN="$(mktemp -d)"; cp -R "$APP" "$PLAIN/Saturn.app"; ln -s /Applications "$PLAIN/Applications"
  hdiutil create -volname "Saturn" -srcfolder "$PLAIN" -ov -format UDZO -fs HFS+ "$OUT" > /dev/null
  rm -rf "$PLAIN"
fi
echo "    $OUT  ($(du -h "$OUT" | cut -f1))"
