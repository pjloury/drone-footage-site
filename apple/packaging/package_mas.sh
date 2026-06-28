#!/usr/bin/env bash
# Build, sign, and export the Mac App Store build of "Aerial Landscapes.app"
# (sandboxed, MAS compile flag — no global hotkeys), then optionally upload to
# App Store Connect.
#
# Screen saver in the App Store build:
#   The sandbox can't write to ~/Library/Screen Savers, so the app ships the
#   .saver embedded in Contents/PlugIns and the menu-bar "Set Up Screen Saver…"
#   item copies it to ~/Downloads + reveals it. The user double-clicks it and
#   macOS performs the install. Gatekeeper assesses that double-clicked .saver:
#   we DON'T staple a notarization ticket ourselves (you don't get the binary
#   back from App Store processing to staple). Instead Apple notarizes the whole
#   submission server-side, which registers the nested saver's cdhash, so an
#   ONLINE Gatekeeper check passes on first launch. VERIFY THIS EMPIRICALLY from
#   a TestFlight/App Store build before relying on it: install the app, run
#   "Set Up Screen Saver…", double-click the file in Downloads, and confirm
#   macOS installs it without an "unidentified developer"/"cannot be opened"
#   block. (Offline first-use is the risk case, since there's no stapled ticket.)
#
# Prereqs:
#   * An app record in App Store Connect with bundle id
#     com.pjloury.aerial-landscapes
#   * App Store Connect API key, or store credentials:
#       xcrun notarytool store-credentials AC_API ...   (or use --apple-id)
#
# Run:           ./packaging/package_mas.sh           # build + export .pkg
#   upload:      UPLOAD=1 ./packaging/package_mas.sh   # also upload to ASC
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="AerialLandscapesMacMAS"
ARCHIVE="build-mas/AppStore/AerialLandscapes.xcarchive"
EXPORT_DIR="build-mas/AppStore/export"

echo "▸ Archiving $SCHEME (sandboxed MAS build) …"
xcodebuild -project AerialLandscapes.xcodeproj -scheme "$SCHEME" \
    -configuration Release -archivePath "$ARCHIVE" archive

echo "▸ Exporting App Store package …"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist packaging/ExportOptions-AppStore.plist \
    -exportPath "$EXPORT_DIR"

PKG=$(ls "$EXPORT_DIR"/*.pkg 2>/dev/null | head -1 || true)
echo "✅  App Store package: ${PKG:-$EXPORT_DIR}"

if [[ "${UPLOAD:-0}" == "1" ]]; then
    echo "▸ Uploading to App Store Connect …"
    # Either --apple-id/--password or --apiKey/--apiIssuer (recommended).
    xcrun altool --upload-app --type macos --file "$PKG" \
        --apple-id "${ASC_APPLE_ID:?set ASC_APPLE_ID}" \
        --password "${ASC_APP_PASSWORD:?set ASC_APP_PASSWORD (app-specific)}"
    echo "✅  Uploaded. Finish submission in App Store Connect."
else
    echo "   Re-run with UPLOAD=1 (and ASC_APPLE_ID / ASC_APP_PASSWORD) to upload,"
    echo "   or drag the .pkg into Transporter."
fi
