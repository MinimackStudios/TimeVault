#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DISTRIBUTION_DIR="$PROJECT_DIR/Distribution"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"

SIGNING_IDENTITY="${TIMEVAULT_CODESIGN_IDENTITY:-}"
ALLOW_ADHOC_SIGNING="${TIMEVAULT_ALLOW_ADHOC_SIGNING:-0}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    AVAILABLE_IDENTITIES=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)
    SIGNING_IDENTITY=$(print -r -- "$AVAILABLE_IDENTITIES" | /usr/bin/awk -F '"' '/Developer ID Application:/ { print $2; exit }')
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        SIGNING_IDENTITY=$(print -r -- "$AVAILABLE_IDENTITIES" | /usr/bin/awk -F '"' '/TimeVault Local/ { print $2; exit }')
    fi
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        SIGNING_IDENTITY=$(print -r -- "$AVAILABLE_IDENTITIES" | /usr/bin/awk -F '"' '/^[[:space:]]*[0-9]+\)/ { print $2; exit }')
    fi
fi

if [[ ( -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ) && "$ALLOW_ADHOC_SIGNING" != "1" ]]; then
    print -u2 "A stable certificate-backed code-signing identity is required for a release DMG."
    print -u2 "Set TIMEVAULT_CODESIGN_IDENTITY to the identity used for previous releases."
    print -u2 "A self-signed identity such as TimeVault Local is sufficient for personal use on this Mac."
    print -u2 "For local testing only, opt in to an ad hoc build with TIMEVAULT_ALLOW_ADHOC_SIGNING=1."
    exit 1
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="-"
    print -u2 "Warning: building an ad hoc-signed app. macOS may require Full Disk Access approval again after an update."
fi

NPM_PREFIX="$(npm prefix --global)"
NPM_ROOT="$(npm root --global)"
CREATE_DMG_BIN="$NPM_PREFIX/bin/create-dmg"
CREATE_DMG_ROOT="$NPM_ROOT/create-dmg"

if [[ ! -x "$CREATE_DMG_BIN" ]]; then
    print -u2 "create-dmg is not installed. Run: npm install --global create-dmg"
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    print -u2 "ffmpeg is required to extend the create-dmg background."
    exit 1
fi

WORK_ROOT="$(mktemp -d /private/tmp/TimeVaultDMG.XXXXXX)"
DERIVED_DATA="$WORK_ROOT/DerivedData"
BASE_DIR="$WORK_ROOT/Base"
MOUNT_DIR="$WORK_ROOT/Mount"
APPCAST_DIR="$WORK_ROOT/Appcast"
RW_DMG="$WORK_ROOT/TimeVault-rw.dmg"
MOUNTED=0

cleanup() {
    if [[ "$MOUNTED" -eq 1 ]]; then
        hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi

    if [[ -n "${WORK_ROOT:-}" && "$WORK_ROOT" == /private/tmp/TimeVaultDMG.* ]]; then
        /bin/rm -rf "$WORK_ROOT"
    fi
}

trap cleanup EXIT INT TERM

mkdir -p "$BASE_DIR" "$MOUNT_DIR" "$APPCAST_DIR" "$OUTPUT_DIR"

xcodebuild \
    -project "$PROJECT_DIR/TimeVault.xcodeproj" \
    -scheme TimeVault \
    -configuration Release \
    -sdk macosx \
    -derivedDataPath "$DERIVED_DATA" \
    build CODE_SIGNING_ALLOWED=NO

APP_PATH="$DERIVED_DATA/Build/Products/Release/TimeVault.app"
VERSION=$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleShortVersionString" \
        "$APP_PATH/Contents/Info.plist"
)
DMG_NAME="TimeVault.dmg"
BASE_DMG="$BASE_DIR/$DMG_NAME"
OUTPUT_DMG="$OUTPUT_DIR/$DMG_NAME"

/usr/bin/codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    "$APP_PATH"

/usr/bin/codesign \
    --verify \
    --deep \
    --strict \
    "$APP_PATH"

"$CREATE_DMG_BIN" \
    --overwrite \
    --no-code-sign \
    --dmg-title=TimeVault \
    "$APP_PATH" \
    "$BASE_DIR"

CREATE_DMG_OUTPUT="$BASE_DIR/TimeVault $VERSION.dmg"
if [[ ! -f "$CREATE_DMG_OUTPUT" ]]; then
    print -u2 "create-dmg did not produce the expected intermediate image:"
    print -u2 "$CREATE_DMG_OUTPUT"
    exit 1
fi
mv "$CREATE_DMG_OUTPUT" "$BASE_DMG"

hdiutil convert "$BASE_DMG" \
    -format UDRW \
    -ov \
    -o "$RW_DMG"

hdiutil attach "$RW_DMG" \
    -nobrowse \
    -noautoopen \
    -mountpoint "$MOUNT_DIR" >/dev/null
MOUNTED=1

cp -p "$DISTRIBUTION_DIR/Open TimeVault.command" "$MOUNT_DIR/"
chmod +x "$MOUNT_DIR/Open TimeVault.command"
cp -p "$DISTRIBUTION_DIR/README.txt" "$MOUNT_DIR/"

ffmpeg \
    -loglevel error \
    -y \
    -i "$CREATE_DMG_ROOT/assets/dmg-background.png" \
    -vf "pad=660:500:0:0:color=0xf0f0f5" \
    -frames:v 1 \
    -c:v tiff \
    -compression_algo lzw \
    "$MOUNT_DIR/.background/dmg-background.tiff"

node \
    "$DISTRIBUTION_DIR/layout-dmg.cjs" \
    "$MOUNT_DIR" \
    "$CREATE_DMG_ROOT/node_modules/ds-store"

hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNTED=0

hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$OUTPUT_DMG"

hdiutil verify "$OUTPUT_DMG"
shasum -a 256 "$OUTPUT_DMG"

SPARKLE_ROOT="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle"
GENERATE_APPCAST="$SPARKLE_ROOT/bin/generate_appcast"

if [[ ! -x "$GENERATE_APPCAST" ]]; then
    print -u2 "Sparkle's generate_appcast tool was not found at:"
    print -u2 "$GENERATE_APPCAST"
    exit 1
fi

cp -p "$OUTPUT_DMG" "$APPCAST_DIR/"

if [[ -f "$DISTRIBUTION_DIR/ReleaseNotes.md" ]]; then
    cp -p \
        "$DISTRIBUTION_DIR/ReleaseNotes.md" \
        "$APPCAST_DIR/${DMG_NAME%.dmg}.md"
fi

"$GENERATE_APPCAST" \
    --download-url-prefix "https://github.com/MinimackStudios/TimeVault/releases/download/v$VERSION/" \
    --embed-release-notes \
    --link "https://github.com/MinimackStudios/TimeVault" \
    --full-release-notes-url "https://github.com/MinimackStudios/TimeVault/releases" \
    -o "$APPCAST_DIR/appcast.xml" \
    "$APPCAST_DIR"

cp -p "$APPCAST_DIR/appcast.xml" "$PROJECT_DIR/appcast.xml"
cp -p "$APPCAST_DIR/appcast.xml" "$OUTPUT_DIR/appcast.xml"

print
print "Created: $OUTPUT_DMG"
print "Created: $OUTPUT_DIR/appcast.xml"
print "Updated: $PROJECT_DIR/appcast.xml"
