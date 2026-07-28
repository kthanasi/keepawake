#!/bin/bash
# Builds KeepAwake.app as a universal (Apple Silicon + Intel) bundle, embeds the
# Sparkle updater, and packages a DMG (for humans) plus a ZIP (for Sparkle).
#
#   ./build.sh                 -> ad-hoc signed
#   ./build.sh "Developer ID Application: Name (TEAMID)"
#                              -> signed for distribution
#
# Version comes from VERSION so the app, appcast, and release tag can't drift.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${1:--}"
VERSION="$(cat VERSION)"
APP="build/KeepAwake.app"
MIN_MACOS="13.0"

SPARKLE_VERSION="2.9.4"
SPARKLE_DIR="vendor/Sparkle-${SPARKLE_VERSION}"
FEED_URL="https://raw.githubusercontent.com/kthanasi/keepawake/main/appcast.xml"
PUBLIC_ED_KEY="JUu2q+A1AuxUCZgDgGodrKTDjKts8w2Md4emWtP6RYM="

# ------------------------------------------------------------------- Sparkle
# Vendored on demand and cached, so the framework never enters git history.
if [ ! -d "$SPARKLE_DIR/Sparkle.framework" ]; then
	echo "==> Fetching Sparkle ${SPARKLE_VERSION}"
	mkdir -p "$SPARKLE_DIR"
	curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
		| tar -xJ -C "$SPARKLE_DIR"
fi

rm -rf build
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# ---------------------------------------------------------------- Info.plist
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>KeepAwake</string>
	<key>CFBundleDisplayName</key><string>KeepAwake</string>
	<key>CFBundleExecutable</key><string>KeepAwake</string>
	<key>CFBundleIdentifier</key><string>com.kthanasi.KeepAwake</string>
	<key>CFBundleIconFile</key><string>KeepAwake</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${VERSION}</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Kotabitus. MIT Licensed.</string>
	<key>NSSupportsAutomaticTermination</key><false/>
	<key>NSSupportsSuddenTermination</key><false/>
	<key>SUFeedURL</key><string>${FEED_URL}</string>
	<key>SUPublicEDKey</key><string>${PUBLIC_ED_KEY}</string>
	<key>SUEnableAutomaticChecks</key><true/>
	<key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# ------------------------------------------------------------------- License
# Ship the license inside the bundle so it travels with the app, not just the repo.
cp LICENSE "$APP/Contents/Resources/LICENSE"

# ---------------------------------------------------------------------- Icon
echo "==> Icon"
swift makeicon.swift build >/dev/null
iconutil -c icns build/KeepAwake.iconset -o "$APP/Contents/Resources/KeepAwake.icns"

# ------------------------------------------------------ Universal executable
echo "==> Compiling (arm64 + x86_64)"
cp -R "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"

for ARCH in arm64 x86_64; do
	swiftc \
		-O -whole-module-optimization \
		-target "${ARCH}-apple-macos${MIN_MACOS}" \
		-F "$SPARKLE_DIR" \
		-framework AppKit -framework IOKit -framework ServiceManagement \
		-framework Sparkle \
		-Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
		-o "build/KeepAwake-${ARCH}" \
		Sources/main.swift
done
lipo -create -output "$APP/Contents/MacOS/KeepAwake" build/KeepAwake-arm64 build/KeepAwake-x86_64
rm -f build/KeepAwake-arm64 build/KeepAwake-x86_64
lipo -info "$APP/Contents/MacOS/KeepAwake"

# --------------------------------------------------------------------- Sign
# Inside-out: Sparkle's helpers first, then the framework, then the app. Using
# --deep here instead would leave the nested helpers improperly signed.
#
# The hardened runtime turns on library validation, which demands that the app
# and the embedded framework share a Team ID. Ad-hoc signatures have no Team ID,
# so requesting it there makes dyld refuse to load Sparkle at launch. Enable it
# only for a real identity, where it is required for notarization anyway.
#
# Note: a plain string rather than an array — macOS ships bash 3.2, where
# expanding an empty array under `set -u` aborts the script.
if [ "$IDENTITY" = "-" ]; then
	SIGN_OPTS=""
else
	SIGN_OPTS="--options runtime"
fi

echo "==> Signing with: ${IDENTITY}"
SPARKLE_IN_APP="$APP/Contents/Frameworks/Sparkle.framework"
for TARGET in \
	"$SPARKLE_IN_APP/Versions/B/XPCServices/Downloader.xpc" \
	"$SPARKLE_IN_APP/Versions/B/XPCServices/Installer.xpc" \
	"$SPARKLE_IN_APP/Versions/B/Updater.app" \
	"$SPARKLE_IN_APP/Versions/B/Autoupdate" \
	"$SPARKLE_IN_APP"
do
	codesign --force $SIGN_OPTS --timestamp=none --sign "$IDENTITY" "$TARGET"
done
codesign --force $SIGN_OPTS --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# ------------------------------------------------------------ DMG (+ ZIP)
echo "==> Packaging"
STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp LICENSE "$STAGE/LICENSE.txt"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "KeepAwake" -srcfolder "$STAGE" -ov -format UDZO \
	"build/KeepAwake-${VERSION}.dmg" >/dev/null
rm -rf "$STAGE" build/KeepAwake.iconset

# Sparkle installs from the ZIP; ditto preserves the signed bundle correctly.
ditto -c -k --keepParent "$APP" "build/KeepAwake-${VERSION}.zip"

echo
echo "Built v${VERSION}:"
echo "  $APP"
echo "  build/KeepAwake-${VERSION}.dmg"
echo "  build/KeepAwake-${VERSION}.zip"
