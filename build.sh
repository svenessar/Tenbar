#!/bin/bash
# Builds dist/Tenbar.app (universal: arm64 + x86_64) and dist/Tenbar-<version>.zip.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DIST="dist"
APP="$DIST/Tenbar.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Tenbar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Tenbar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"

ditto -c -k --keepParent "$APP" "$DIST/Tenbar-$VERSION.zip"
echo "App:    $APP"
echo "Archiv: $DIST/Tenbar-$VERSION.zip"
