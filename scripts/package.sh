#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash scripts/build.sh
VERSION="$(tr -d '\n' < VERSION)"
NAME="MirrorReward-$VERSION-macos-universal"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/MirrorReward-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto --norsrc --noextattr dist/MirrorReward.app "$STAGING/MirrorReward.app"
xattr -cr "$STAGING/MirrorReward.app"
codesign --verify --deep --strict "$STAGING/MirrorReward.app"
ln -s /Applications "$STAGING/Applications"
cp README.md "$STAGING/README.md"
hdiutil create -volname MirrorReward -srcfolder "$STAGING" -format UDZO -ov "dist/$NAME.dmg"
ditto -c -k --norsrc --noextattr --keepParent "$STAGING/MirrorReward.app" "dist/$NAME.zip"
(cd dist && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
printf 'Packages: %s/dist\n' "$ROOT"
