#!/usr/bin/env bash
# Builds a distributable Airpisode DMG.
#
# By default the bundle ships keyless (each person supplies their own TMDB key on first
# launch) and ad-hoc signed, which is enough to run the app but NOT to install updates:
# Sparkle requires every update to be signed with the same Developer ID as the running app.
#
# For a release that can update itself:
#   AIRPISODE_SIGN_IDENTITY="Developer ID Application: …" \
#   DEVELOPMENT_TEAM=ABCDE12345 \
#   NOTARIZE=1 \
#   ./Scripts/build-dmg.sh
#
# Overrides:
#   VERSION   marketing version (default: MARKETING_VERSION from project.yml)
#   BUILD     build number Sparkle compares (default: UTC timestamp)
set -euo pipefail

APP_NAME="Airpisode"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DIST="$ROOT/dist"

SIGN_IDENTITY="${AIRPISODE_SIGN_IDENTITY:--}"
BUILD_NUMBER="${BUILD:-$(date -u +%Y%m%d%H%M)}"

cd "$ROOT"
xcodegen generate

BUILD_ARGS=(
  -project "$APP_NAME.xcodeproj"
  -scheme "$APP_NAME"
  -configuration Release
  -derivedDataPath "$BUILD_DIR"
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  # Ship with an empty key: the app prompts each user for their own on first launch.
  TMDB_API_KEY=""
)
if [ -n "${VERSION:-}" ]; then
  BUILD_ARGS+=(MARKETING_VERSION="$VERSION")
fi
if [ "$SIGN_IDENTITY" != "-" ]; then
  [ -n "${DEVELOPMENT_TEAM:-}" ] || { echo "Set DEVELOPMENT_TEAM for a Developer ID build." >&2; exit 1; }
  # Notarization requires the hardened runtime, and Sparkle validates that the update
  # carries the same Team ID as the running app.
  BUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
    ENABLE_HARDENED_RUNTIME=YES
    OTHER_CODE_SIGN_FLAGS="--timestamp"
  )
fi

xcodebuild "${BUILD_ARGS[@]}" build

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "Build product not found at $APP" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

# Re-sign ad-hoc builds because touching bundle contents after Xcode's pass invalidates
# the signature. Developer ID builds are already signed by xcodebuild.
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

rm -rf "$DIST/stage"
mkdir -p "$DIST"
rm -f "$DMG"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

echo "Built $DMG (build $BUILD_NUMBER)"

if [ "${NOTARIZE:-0}" = "1" ]; then
  "$ROOT/Scripts/notarize.sh" "$DMG"
fi
