#!/usr/bin/env bash
#
# MacBon Release Builder
# ----------------------
# Builds, signs, notarizes, and packages MacBon.dmg for distribution.
#
# Prerequisites (on the build Mac):
#   1. "Developer ID Application" certificate installed in keychain
#   2. Notarization credentials stored as a keychain profile (one-time setup):
#        xcrun notarytool store-credentials MacBonNotary \
#          --apple-id YOUR_APPLE_ID \
#          --team-id YOUR_TEAM_ID \
#          --password APP_SPECIFIC_PASSWORD
#      (Get app-specific password at https://appleid.apple.com/account/manage)
#
# Usage:
#   ./release.sh             # build + notarize + dmg → ./dist/MacBon.dmg
#   ./release.sh --skip-notarize   # skip notarization (for quick local test)
#
set -euo pipefail

# ── Config ──────────────────────────────────────────────────
PROJECT="MacBon.xcodeproj"
SCHEME="MacBon"
APP_NAME="MacBon"
NOTARY_PROFILE="MacBonNotary"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${ROOT_DIR}/dist"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

SKIP_NOTARIZE=0
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=1

# ── Helpers ─────────────────────────────────────────────────
log()  { printf "\033[1;34m▸\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m✗\033[0m %s\n" "$*"; exit 1; }

# ── Pre-flight ──────────────────────────────────────────────
log "Pre-flight checks"
command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v xcrun      >/dev/null || fail "xcrun not found"

CERT_COUNT=$(security find-identity -v -p codesigning | grep -c "Developer ID Application" || true)
[[ $CERT_COUNT -gt 0 ]] || fail "No 'Developer ID Application' certificate in keychain"
ok "Developer ID cert present"

# Get version
VERSION=$(grep -A 1 "CFBundleShortVersionString" TapMac/Info.plist | tail -1 | sed -E 's/.*<string>(.*)<\/string>.*/\1/')
log "Building MacBon ${VERSION}"

# ── Clean ───────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Archive ─────────────────────────────────────────────────
log "Archiving (Release config)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "platform=macOS" \
  archive \
  | xcpretty || true

[[ -d "$ARCHIVE_PATH" ]] || fail "Archive failed"
ok "Archive built at $ARCHIVE_PATH"

# ── Export with Developer ID ────────────────────────────────
log "Exporting signed .app"

cat > "${BUILD_DIR}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
  | xcpretty || true

[[ -d "${EXPORT_DIR}/${APP_NAME}.app" ]] || fail "Export failed"
ok "Exported ${APP_NAME}.app"

# ── Notarize (optional) ─────────────────────────────────────
if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    log "Notarizing (this may take 1-5 minutes)"
    ZIP_FOR_NOTARY="${BUILD_DIR}/${APP_NAME}.zip"
    /usr/bin/ditto -c -k --keepParent "${EXPORT_DIR}/${APP_NAME}.app" "$ZIP_FOR_NOTARY"

    xcrun notarytool submit "$ZIP_FOR_NOTARY" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        || fail "Notarization failed — check 'xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE'"

    log "Stapling notarization to .app"
    xcrun stapler staple "${EXPORT_DIR}/${APP_NAME}.app" || fail "Staple failed"
    ok "Notarized and stapled"
else
    log "Skipping notarization (--skip-notarize)"
fi

# ── Build DMG ───────────────────────────────────────────────
log "Building DMG"
DMG_STAGING="${BUILD_DIR}/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "${EXPORT_DIR}/${APP_NAME}.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "MacBon ${VERSION}" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    >/dev/null

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    # Notarize the DMG itself (best practice)
    log "Notarizing DMG"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        || fail "DMG notarization failed"
    xcrun stapler staple "$DMG_PATH" || fail "DMG staple failed"
fi

ok "DMG built at $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

# ── Summary ─────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Release ${VERSION} ready"
echo "═══════════════════════════════════════════════════════════"
echo "  DMG:  $DMG_PATH"
echo
echo "Next steps:"
echo "  1. Test:    open $DMG_PATH"
echo "  2. Tag:     git tag v${VERSION} && git push origin v${VERSION}"
echo "  3. Release: gh release create v${VERSION} \\"
echo "                $DMG_PATH \\"
echo "                --title \"MacBon ${VERSION}\" \\"
echo "                --notes-file RELEASE_NOTES.md"
echo "═══════════════════════════════════════════════════════════"
