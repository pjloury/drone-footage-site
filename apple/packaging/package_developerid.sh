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

# ── Build a drag-to-Applications DMG around the stapled app ────────────────
# The .app is already notarized+stapled (works offline on first launch). We
# also notarize+staple the DMG itself so the downloaded file passes Gatekeeper
# cleanly before it's even opened.
DMG="build/DeveloperID/Aerial Landscapes.dmg"
echo "▸ Building DMG …"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Aerial Landscapes" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "▸ Notarizing + stapling the DMG …"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "✅  Distributable DMG: $DMG"
echo "   Host it anywhere; users drag “Aerial Landscapes” into Applications."
