#!/bin/bash
# Builds build/YaikusStudio-<version>.dmg. Usage:
#   ./packaging/package.sh                                   → DMG with an ad-hoc signature (testing; Gatekeeper will ask for "Open Anyway")
#   SIGN_ID="Developer ID Application: Nombre (TEAMID)" NOTARY_PROFILE=yaikus-notary ./packaging/package.sh
#                                                            → signs with hardened runtime, notarizes and staples the ticket
#   (CI) NOTARY_APPLE_ID / NOTARY_TEAM_ID / NOTARY_PASSWORD instead of NOTARY_PROFILE
# Once, to set up notarization:  xcrun notarytool store-credentials yaikus-notary --apple-id <id> --team-id <TEAMID> --password <app-specific-password>
set -e
cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
./packaging/build_app.sh >/dev/null
APP="build/Yaikus Studio.app"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="build/YaikusStudio-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Yaikus Studio" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

SIGN="${SIGN_ID:--}"
if [ "$SIGN" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN" "$DMG"
  if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait && xcrun stapler staple "$DMG"
  elif [ -n "$NOTARY_APPLE_ID" ] && [ -n "$NOTARY_TEAM_ID" ] && [ -n "$NOTARY_PASSWORD" ]; then
    xcrun notarytool submit "$DMG" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait && xcrun stapler staple "$DMG"
  else
    echo "Signed, but not notarized (NOTARY_PROFILE is missing)."
  fi
else
  echo "Ad-hoc signature: for local testing only."
fi
hdiutil verify -quiet "$DMG" && echo "Done: $PWD/$DMG ($(du -h "$DMG" | cut -f1))"
