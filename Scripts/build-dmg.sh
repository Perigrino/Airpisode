#!/usr/bin/env bash
# Builds a distributable Airpisode DMG with no baked-in TMDB key,
# so each person supplies their own on first launch.
set -euo pipefail

APP_NAME="Airpisode"
VERSION="0.2.3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

cd "$ROOT"
xcodegen generate

# Ship with an empty key: the app prompts each user for their own on first launch.
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath "$BUILD" \
  TMDB_API_KEY="" build

APP="$BUILD/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "Build product not found at $APP" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "Built $DMG"
