#!/bin/bash
# Build SparkClean.app from the SwiftPM package.
# Usage: ./Scripts/build-app.sh [--universal]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="SparkClean"
BUNDLE_ID="fun.sparkclean.app"
BUILD_DIR=".build"
APP_DIR="build/SparkClean.app"
CONTENTS="$APP_DIR/Contents"

echo "==> Building $CONFIGURATION binary"
if [[ "${1:-}" == "--universal" ]]; then
    echo "    (universal: arm64 + x86_64)"
    swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64
else
    swift build -c "$CONFIGURATION"
fi

BIN="$BUILD_DIR/$CONFIGURATION/SparkClean"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Resources/GPL-3.0.txt "$CONTENTS/Resources/GPL-3.0.txt"
cp Resources/COPYRIGHT.txt "$CONTENTS/Resources/COPYRIGHT.txt"
cp Resources/THIRD_PARTY_NOTICES.txt "$CONTENTS/Resources/THIRD_PARTY_NOTICES.txt"
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null || {
    echo "    (no AppIcon.icns yet — run Scripts/make-icon.sh first)"
}

if [[ "${CODE_SIGN:-1}" == "1" ]]; then
    echo "==> Ad-hoc code signing"
    codesign --force --sign - \
        --entitlements Resources/SparkClean.entitlements \
        "$APP_DIR" 2>/dev/null || codesign --force --sign - "$APP_DIR"
fi

echo "==> Done: $APP_DIR"
[[ -d "$APP_DIR" ]] && du -sh "$APP_DIR"
