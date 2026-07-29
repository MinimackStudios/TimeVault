#!/bin/zsh

set -euo pipefail

APP_PATH="/Applications/TimeVault.app"
EXPECTED_BUNDLE_ID="com.minimackstudios.TimeVault"

if [[ ! -d "$APP_PATH" ]]; then
    /usr/bin/osascript -e 'display alert "Move TimeVault First" message "Drag TimeVault.app onto the Applications shortcut in the disk image, then run this file again." as warning'
    exit 1
fi

BUNDLE_ID=$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleIdentifier" \
        "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
)

if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
    /usr/bin/osascript -e 'display alert "TimeVault Could Not Be Verified" message "The application in your Applications folder does not have the expected bundle identifier." as warning'
    exit 1
fi

if ! /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH"; then
    /usr/bin/osascript -e 'display alert "TimeVault Could Not Be Opened" message "Control-click TimeVault in Applications, choose Open, then confirm that you want to open it." as warning'
    exit 1
fi

/usr/bin/open "$APP_PATH"
