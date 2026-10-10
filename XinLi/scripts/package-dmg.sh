#!/bin/bash
# Package an existing signed 心历 app without rebuilding or changing its signature.
# Usage: scripts/package-dmg.sh <心历.app> <output.dmg>
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <心历.app> <output.dmg>" >&2
    exit 1
fi

XINLI_DMG_PROJECT=$(cd "$(dirname "$0")/.." && pwd)
XINLI_DMG_NOTES="$XINLI_DMG_PROJECT/Resources/安装说明.txt"
if [ ! -d "$1" ]; then
    echo "App bundle does not exist: $1" >&2
    exit 1
fi
XINLI_DMG_APP=$(cd "$1" && pwd)
case "$XINLI_DMG_APP" in
    *.app) ;;
    *) echo "Expected an .app bundle: $XINLI_DMG_APP" >&2; exit 1 ;;
esac
case "$2" in
    *.dmg) ;;
    *) echo "Output must have the .dmg extension: $2" >&2; exit 1 ;;
esac
if [ ! -f "$XINLI_DMG_NOTES" ]; then
    echo "Missing installation instructions: $XINLI_DMG_NOTES" >&2
    exit 1
fi

verify_app() {
    local xinli_bundle="$1"
    local xinli_executable
    /usr/bin/plutil -lint "$xinli_bundle/Contents/Info.plist" >/dev/null
    xinli_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$xinli_bundle/Contents/Info.plist")
    case "$xinli_executable" in
        ""|*/*|.|..) echo "Invalid CFBundleExecutable: $xinli_executable" >&2; return 1 ;;
    esac
    if [ ! -f "$xinli_bundle/Contents/MacOS/$xinli_executable" ] || [ ! -x "$xinli_bundle/Contents/MacOS/$xinli_executable" ]; then
        echo "Missing executable or execute permission: $xinli_bundle/Contents/MacOS/$xinli_executable" >&2
        return 1
    fi
    /usr/bin/lipo -archs "$xinli_bundle/Contents/MacOS/$xinli_executable" >/dev/null
    /usr/bin/codesign --verify --deep --strict "$xinli_bundle"
}

verify_app "$XINLI_DMG_APP"
XINLI_DMG_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$XINLI_DMG_APP/Contents/Info.plist")
XINLI_DMG_SIGNATURE=$(/usr/bin/codesign -d --verbose=2 "$XINLI_DMG_APP" 2>&1)
XINLI_DMG_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/xinli-dmg.XXXXXX")
trap 'rm -rf "$XINLI_DMG_TEMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
XINLI_DMG_CONTENTS="$XINLI_DMG_TEMP/contents"
mkdir -p "$XINLI_DMG_CONTENTS"
/usr/bin/ditto "$XINLI_DMG_APP" "$XINLI_DMG_CONTENTS/心历.app"
verify_app "$XINLI_DMG_CONTENTS/心历.app"
/bin/ln -s /Applications "$XINLI_DMG_CONTENTS/Applications"
/usr/bin/ditto "$XINLI_DMG_NOTES" "$XINLI_DMG_CONTENTS/安装说明.txt"

# UDZO is a compressed read-only image. Copying the complete bundle preserves
# permissions and signed resources; no signing or quarantine attributes change.
/usr/bin/hdiutil create -volname "心历" -srcfolder "$XINLI_DMG_CONTENTS" \
    -fs HFS+ -format UDZO "$XINLI_DMG_TEMP/心历.dmg"
/usr/bin/hdiutil verify "$XINLI_DMG_TEMP/心历.dmg"
if [ -d "$2" ]; then
    echo "Output is a directory: $2" >&2
    exit 1
fi
mkdir -p "$(dirname "$2")"
/bin/mv -f "$XINLI_DMG_TEMP/心历.dmg" "$2"
echo "Packaged 心历 $XINLI_DMG_VERSION: $2"
echo "DMG packaging does not provide Developer ID signing or Apple notarization."
case "$XINLI_DMG_SIGNATURE" in
    *Signature=adhoc*) echo "Warning: this app is ad-hoc signed and is not Developer ID signed." >&2 ;;
esac
