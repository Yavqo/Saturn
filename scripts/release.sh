#!/bin/bash
# Build a release of Saturn and package it the way the in-app updater expects.
#
#   scripts/release.sh 0.2.0                     build dist/Saturn-0.2.0.zip only
#   scripts/release.sh 0.2.0 --publish           also create the GitHub release v0.2.0 (needs `gh auth login`)
#   scripts/release.sh 0.2.0 --publish --notes "What's new"
#
# Installed copies of Saturn check the latest GitHub release of Yavqo/Saturn; when its version is
# higher than theirs, an Update button appears. The release must contain exactly one Saturn*.zip (used for
# in-app updates); the .dmg next to it is the installer people download for the first time.
set -euo pipefail

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh <version> [--publish] [--notes \"text\"]"; exit 1; }
shift
PUBLISH=0; NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --notes) shift; NOTES="${1:-}" ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
  shift
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] || { echo "version must look like 1.2.3 (or 1.2.3-beta1)"; exit 1; }

cd "$(dirname "$0")/.."
BUILD_DIR="build-release"   # separate from the everyday build/ so its version stays untouched

echo "==> Building Saturn $VERSION"
cmake -S . -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DSATURN_VERSION="$VERSION" > /dev/null
cmake --build "$BUILD_DIR" -j4

echo "==> Packaging"
rm -rf dist && mkdir -p dist/pkg
cp -R "$BUILD_DIR/saturn.app" dist/pkg/Saturn.app
codesign --force --deep -s - dist/pkg/Saturn.app      # ad-hoc signature (no Apple Developer ID yet)
codesign --verify --deep dist/pkg/Saturn.app
ditto -c -k --sequesterRsrc --keepParent dist/pkg/Saturn.app "dist/Saturn-$VERSION.zip"
echo "    dist/Saturn-$VERSION.zip  ($(du -h "dist/Saturn-$VERSION.zip" | cut -f1))"
echo "    sha256 $(shasum -a 256 "dist/Saturn-$VERSION.zip" | cut -d' ' -f1)"

echo "==> Disk image"
scripts/make-dmg.sh dist/pkg/Saturn.app "dist/Saturn-$VERSION.dmg"

if [ "$PUBLISH" = 1 ]; then
  command -v gh > /dev/null || { echo "gh (GitHub CLI) is not installed"; exit 1; }
  echo "==> Publishing v$VERSION to Yavqo/Saturn"
  FLAGS=()
  [[ "$VERSION" == *-* ]] && FLAGS+=(--prerelease)     # beta tags are not offered as updates
  if [ -n "$NOTES" ]; then FLAGS+=(--notes "$NOTES"); else FLAGS+=(--generate-notes); fi
  gh release create "v$VERSION" "dist/Saturn-$VERSION.zip" "dist/Saturn-$VERSION.dmg" --repo Yavqo/Saturn --title "Saturn $VERSION" "${FLAGS[@]}"
  echo "Done. Installed copies will offer this update within about 6 hours (or via Saturn > Check for Updates)."
else
  echo "Built only. Add --publish to create the GitHub release."
fi
