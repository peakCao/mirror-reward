#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '\n' < VERSION)"
BUILD="$ROOT/.build"
APP="$ROOT/dist/MirrorReward.app"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
# Swift requires the executable's top-level statements to live in main.swift.
cp engine/ad_watcher.swift "$BUILD/main.swift"
for ARCH in arm64 x86_64; do
    swiftc -swift-version 5 -O -target "$ARCH-apple-macos15.0" -debug-prefix-map "$ROOT"=. \
        engine/Runtime.swift "$BUILD/main.swift" -o "$BUILD/ad_watcher-$ARCH"
    swiftc -swift-version 5 -O -target "$ARCH-apple-macos15.0" -debug-prefix-map "$ROOT"=. \
        app/Runner.swift app/MirrorRewardApp.swift -o "$BUILD/MirrorReward-$ARCH"
done
lipo -create "$BUILD/ad_watcher-arm64" "$BUILD/ad_watcher-x86_64" -output "$APP/Contents/MacOS/ad_watcher"
lipo -create "$BUILD/MirrorReward-arm64" "$BUILD/MirrorReward-x86_64" -output "$APP/Contents/MacOS/MirrorReward"
swift scripts/make-icon.swift "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
xattr -cr "$APP"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then SIGN_ARGS+=(--options runtime --timestamp); fi
codesign "${SIGN_ARGS[@]}" --identifier io.github.peakCao.MirrorReward.engine "$APP/Contents/MacOS/ad_watcher"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
