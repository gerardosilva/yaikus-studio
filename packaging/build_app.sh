#!/bin/bash
# Builds (universal arm64+x86_64) and assembles "Yaikus Studio.app" in build/.
#   SIGN_ID="Developer ID Application: …"   real signing (default: ad-hoc signature)
#   SANDBOX=0                               without App Sandbox (debugging only)
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="$(tr -d '[:space:]' < VERSION)"
# Each architecture is built separately and merged with lipo: SwiftPM's double `--arch` mode produced a binary
# that crashed when instantiating AVPlayerView (a Swift runtime metadata failure).
ARCHS="${ARCHS:-arm64 x86_64}"
SLICES=()
for a in $ARCHS; do
  swift build -c release --arch "$a" --scratch-path ".build-$a" 2>&1 | tail -1
  SLICES+=("$(swift build -c release --arch "$a" --scratch-path ".build-$a" --show-bin-path)/YaikusStudio")
done
mkdir -p build
lipo -create "${SLICES[@]}" -output build/YaikusStudio.bin
BIN="build/YaikusStudio.bin"
APP="build/Yaikus Studio.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/YaikusStudio"; rm -f "$BIN"
[ -f Resources/Icon/AppIcon.icns ] && cp Resources/Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Yaikus Studio</string>
<key>CFBundleDisplayName</key><string>Yaikus Studio</string>
<key>CFBundleIdentifier</key><string>com.yaikus.studio</string>
<key>CFBundleExecutable</key><string>YaikusStudio</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.video</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
<key>NSHumanReadableCopyright</key><string>© Yaikus Studio</string>
</dict></plist>
PL
SIGN="${SIGN_ID:--}"
FLAGS=(--force --sign "$SIGN")
[ "$SIGN" != "-" ] && FLAGS+=(--options runtime --timestamp)
[ "${SANDBOX:-1}" = "1" ] && FLAGS+=(--entitlements packaging/Yaikus.entitlements)
codesign "${FLAGS[@]}" "$APP"
codesign --verify --strict "$APP"
echo "Done: $ROOT/$APP"
