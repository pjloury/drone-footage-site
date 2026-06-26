#!/usr/bin/env bash
# Build, sign, notarize, and staple the FULL Developer ID build of
# "Aerial Landscapes.app" (hotkeys + embedded screen saver) for distribution
# from your own site — NOT the Mac App Store.
#
# One-time setup (stores your notarization credentials in the keychain):
#   xcrun notarytool store-credentials AC_NOTARY \
#       --apple-id "you@example.com" \
#       --team-id D2GRT69L42 \
#       --password "<app-specific-password>"
#
# Then just run:  ./packaging/package_developerid.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="AerialLandscapesMac"
ARCHIVE="build/DeveloperID/AerialLandscapes.xcarchive"
EXPORT_DIR="build/DeveloperID/export"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

echo "▸ Archiving $SCHEME …"
xcodebuild -project AerialLandscapes.xcodeproj -scheme "$SCHEME" \
    -configuration Release -archivePath "$ARCHIVE" archive

echo "▸ Exporting Developer ID app …"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist packaging/ExportOptions-DeveloperID.plist \
    -exportPath "$EXPORT_DIR"

APP="$EXPORT_DIR/Aerial Landscapes.app"
ZIP="build/DeveloperID/Aerial Landscapes.zip"

echo "▸ Zipping for notarization …"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Submitting to Apple notary service (profile: $PROFILE) …"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling ticket …"
xcrun stapler staple "$APP"
xcrun stapler staple "$APP/Contents/PlugIns/"*.saver 2>/dev/null || true

echo "✅  Notarized app at: $APP"
echo "   Distribute the stapled .app (zip or in a DMG) from your site."
