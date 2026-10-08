#!/bin/bash
# Builds build/YaikusStudio-<version>.dmg. Usage:
#   ./packaging/package.sh                                   → DMG with an ad-hoc signature (testing; Gatekeeper will ask for "Open Anyway")
#   SIGN_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=yaikus-notary ./packaging/package.sh
#                                                            → signs with hardened runtime, notarizes and staples BOTH the app and the DMG
#   (CI) NOTARY_APPLE_ID / NOTARY_TEAM_ID / NOTARY_PASSWORD instead of NOTARY_PROFILE
# Once, to set up notarization:  xcrun notarytool store-credentials yaikus-notary --apple-id <id> --team-id <TEAMID> --password <app-specific-password>
#
# The app is notarized and stapled first, then put in the DMG, which is signed, notarized and stapled too.
# A stapled app carries its own ticket, so it opens without an online check after being dragged out of the DMG.
set -e
cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
./packaging/build_app.sh >/dev/null
APP="build/Yaikus Studio.app"
DMG="build/YaikusStudio-$VERSION.dmg"
SIGN="${SIGN_ID:--}"

# Submits a file to Apple's notary service and fails unless it is accepted.
notarize() {
  local out
  if [ -n "$NOTARY_PROFILE" ]; then
    out="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
  else
    out="$(xcrun notarytool submit "$1" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait 2>&1)"
  fi
  echo "$out" | tail -4
  echo "$out" | grep -q "status: Accepted" || { echo "Notarization failed for $1"; exit 1; }
}

CAN_NOTARIZE=0
if [ "$SIGN" != "-" ]; then
  if [ -n "$NOTARY_PROFILE" ] || { [ -n "$NOTARY_APPLE_ID" ] && [ -n "$NOTARY_TEAM_ID" ] && [ -n "$NOTARY_PASSWORD" ]; }; then CAN_NOTARIZE=1; fi
fi

if [ "$CAN_NOTARIZE" = "1" ]; then
  ZIPDIR="$(mktemp -d)"
  ditto -c -k --keepParent "$APP" "$ZIPDIR/app.zip"
  notarize "$ZIPDIR/app.zip"
  xcrun stapler staple "$APP"
  rm -rf "$ZIPDIR"
fi

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Yaikus Studio" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [ "$SIGN" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN" "$DMG"
  if [ "$CAN_NOTARIZE" = "1" ]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
  else
    echo "Signed, but not notarized (set NOTARY_PROFILE or the NOTARY_* variables)."
  fi
else
  echo "Ad-hoc signature: for local testing only."
fi
hdiutil verify -quiet "$DMG" && echo "Done: $PWD/$DMG ($(du -h "$DMG" | cut -f1))"
