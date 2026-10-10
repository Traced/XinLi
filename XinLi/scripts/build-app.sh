#!/bin/bash
# Build native 心历 with SwiftPM. macOS 14+, Xcode 16+ (Swift 6).
# Usage: scripts/build-app.sh [universal|arm64|x86_64]
# Outputs build/心历.app and versioned ZIP / DMG packages.
# Default ad-hoc build is not sandboxed, preserving existing
# non-sandbox preferences and data. Set XINLI_SANDBOX=1 for sandbox signing.
# Optional: VERSION, SWIFT_BUILD_PATH, XINLI_SIGNING_IDENTITY.
# CHRONOCAL_SANDBOX / CHRONOCAL_SIGNING_IDENTITY remain compatible fallbacks.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH=${1:-universal}
case "$ARCH" in
    universal) ARCHS=(arm64 x86_64); SUFFIX=Universal ;;
    arm64)     ARCHS=(arm64);        SUFFIX=AppleSilicon ;;
    x86_64)    ARCHS=(x86_64);       SUFFIX=Intel ;;
    *) echo "Unknown architecture: $ARCH (use universal, arm64, or x86_64)" >&2; exit 1 ;;
esac

BUILD_PATH=${SWIFT_BUILD_PATH:-.build}
XINLI_BUILD_SANDBOX=${XINLI_SANDBOX:-${CHRONOCAL_SANDBOX:-0}}
XINLI_BUILD_SIGNING_IDENTITY=${XINLI_SIGNING_IDENTITY:-${CHRONOCAL_SIGNING_IDENTITY:--}}
mkdir -p build
STAGING="build/.xinli-staging-$$"
APP="$STAGING/心历.app"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BINARIES=()
RESOURCE_PATH=""
for architecture in "${ARCHS[@]}"; do
    swift build -c release --product XinLi --arch "$architecture" --scratch-path "$BUILD_PATH"
    BIN_PATH=$(swift build -c release --product XinLi --arch "$architecture" --scratch-path "$BUILD_PATH" --show-bin-path)
    BINARIES+=("$BIN_PATH/XinLi")
    if [ -z "$RESOURCE_PATH" ]; then RESOURCE_PATH="$BIN_PATH/XinLi_XinLi.bundle"; fi
done
lipo -create -output "$APP/Contents/MacOS/XinLi" "${BINARIES[@]}"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ChronoCalIcon.icns "$APP/Contents/Resources/"
cp ../LICENSE "$APP/Contents/Resources/LICENSE"
if [ ! -d "$RESOURCE_PATH" ]; then
    echo "Missing SwiftPM resource bundle: $RESOURCE_PATH" >&2
    exit 1
fi
ditto "$RESOURCE_PATH" "$APP/Contents/Resources/XinLi_XinLi.bundle"
CORE_RESOURCE_PATH="$(dirname "$RESOURCE_PATH")/XinLi_LunarCore.bundle"
if [ ! -d "$CORE_RESOURCE_PATH" ]; then
    echo "Missing lunar-go resource bundle: $CORE_RESOURCE_PATH" >&2
    exit 1
fi
ditto "$CORE_RESOURCE_PATH" "$APP/Contents/Resources/XinLi_LunarCore.bundle"
ditto Resources/Calendar "$APP/Contents/Resources/Calendar"
mkdir -p "$APP/Contents/Resources/calendar-data"
cp ../docs/data/holidays.json "$APP/Contents/Resources/calendar-data/"

PLIST_VERSION=${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}
PLIST_VERSION=${PLIST_VERSION#v}
DISPLAY_VERSION=$PLIST_VERSION
while [[ "$DISPLAY_VERSION" == *.0 ]]; do DISPLAY_VERSION=${DISPLAY_VERSION%.0}; done
DISPLAY_VERSION="v$DISPLAY_VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PLIST_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date -u +%Y%m%d%H%M)" "$APP/Contents/Info.plist"
if [ "$XINLI_BUILD_SANDBOX" = "1" ]; then
    codesign --force --sign "$XINLI_BUILD_SIGNING_IDENTITY" --entitlements Resources/ChronoCal.entitlements "$APP"
else
    codesign --force --sign "$XINLI_BUILD_SIGNING_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

# Replace complete bundles only after successful compilation and signing.
rm -rf build/心历.app
mv "$APP" build/心历.app
ZIP="心历-$DISPLAY_VERSION-$SUFFIX.zip"
rm -f "build/$ZIP"
ditto -c -k --keepParent build/心历.app "build/$ZIP"
lipo -info build/心历.app/Contents/MacOS/XinLi
DMG="心历-$DISPLAY_VERSION-$SUFFIX.dmg"
./scripts/package-dmg.sh build/心历.app "build/$DMG"
echo "Built build/心历.app, build/$ZIP and build/$DMG"
