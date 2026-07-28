#!/bin/bash
# Cuts a release: bumps the version, builds, signs the update with the EdDSA key
# from the Keychain, regenerates appcast.xml, and publishes to GitHub.
#
#   ./release.sh 1.1 "Fixes the timer resetting on wake."
#
# The appcast lives on the main branch and is served over raw.githubusercontent,
# which is what the app polls. Committing it is what actually ships the update.
set -euo pipefail
cd "$(dirname "$0")"

NEW_VERSION="${1:?usage: ./release.sh <version> [release notes]}"
NOTES="${2:-}"
SPARKLE_DIR="vendor/Sparkle-2.9.4"
REPO="kthanasi/keepawake"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
	echo "error: working tree is dirty — commit before releasing." >&2
	exit 1
fi

echo "==> Version $NEW_VERSION"
echo "$NEW_VERSION" > VERSION
./build.sh "${IDENTITY:--}"

# Only the newest archive is staged. generate_appcast applies one download-URL
# prefix to everything in the folder, and each version lives under its own
# release tag, so mixing versions here would emit wrong URLs for the old ones.
# Sparkle only needs the latest item to offer an update.
rm -rf releases && mkdir -p releases
cp "build/KeepAwake-${NEW_VERSION}.zip" releases/

echo "==> Signing update and regenerating appcast"
"$SPARKLE_DIR/bin/generate_appcast" \
	--download-url-prefix "https://github.com/${REPO}/releases/download/v${NEW_VERSION}/" \
	--link "https://github.com/${REPO}" \
	-o appcast.xml \
	releases/

echo "==> Publishing"
git add VERSION appcast.xml
git commit -q -m "Release v${NEW_VERSION}${NOTES:+ — $NOTES}"
git push -q origin main

gh release create "v${NEW_VERSION}" \
	"build/KeepAwake-${NEW_VERSION}.dmg" \
	"build/KeepAwake-${NEW_VERSION}.zip" \
	--repo "$REPO" \
	--title "KeepAwake ${NEW_VERSION}" \
	--notes "${NOTES:-Maintenance release.}"

echo
echo "Released v${NEW_VERSION}. Existing installs will offer it within 24h."
