#!/usr/bin/env bash
# Signs and publishes the appcast for the DMG(s) in dist/.
#
# Usage:
#   Scripts/build-dmg.sh                      # produces dist/Airpisode-<version>.dmg
#   Scripts/make-appcast.sh                   # signs it and writes dist/feed/appcast.xml
#
# The EdDSA private key is read from, in order:
#   1. SPARKLE_ED_KEY_FILE        path to a key file exported with `generate_keys -x`
#   2. SPARKLE_ED_PRIVATE_KEY     the key itself, for CI secrets (never echoed)
#   3. the login Keychain         the default when you ran `generate_keys` locally
#
# Optional:
#   DOWNLOAD_PREFIX   URL prefix for the DMG links, e.g.
#                     https://github.com/owner/Airpisode/releases/download/v0.3.0
#                     Defaults to the GitHub release URL for the version in the DMG name.
set -euo pipefail

APP_NAME="Airpisode"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
FEED="$DIST/feed"

"$ROOT/Scripts/fetch-sparkle-tools.sh" >/dev/null
TOOLS="$ROOT/.build/sparkle-tools/bin"

# The newest DMG is the release being published; older ones stay in dist/ for the
# appcast history but are not re-signed with this release's download URL.
NEWEST="$(ls -t "$DIST/$APP_NAME-"*.dmg 2>/dev/null | head -1)"
[ -n "$NEWEST" ] || { echo "No $APP_NAME-*.dmg in $DIST. Run Scripts/build-dmg.sh first." >&2; exit 1; }

VERSION="$(basename "$NEWEST" | sed -E "s/^$APP_NAME-(.*)\.dmg$/\1/")"

REPO_URL="$(git -C "$ROOT" config --get remote.origin.url || true)"
REPO_PATH="$(printf '%s' "$REPO_URL" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"

if [ -z "${DOWNLOAD_PREFIX:-}" ]; then
  [ -n "$REPO_PATH" ] || { echo "Set DOWNLOAD_PREFIX: no GitHub remote found to build download URLs from." >&2; exit 1; }
  DOWNLOAD_PREFIX="https://github.com/$REPO_PATH/releases/download/v$VERSION"
fi
# generate_appcast resolves each archive name against this URL, and a base without a
# trailing slash would drop its last path component.
case "$DOWNLOAD_PREFIX" in
  */) ;;
  *) DOWNLOAD_PREFIX="$DOWNLOAD_PREFIX/" ;;
esac

# generate_appcast works on a folder of archives and re-uses any appcast already there,
# so keep the previous feed and add this release to it.
mkdir -p "$FEED"
cp -f "$NEWEST" "$FEED/"
NOTES="$DIST/$APP_NAME-$VERSION.md"
if [ -f "$NOTES" ]; then cp -f "$NOTES" "$FEED/"; fi

ARGS=(
  "$FEED"
  --download-url-prefix "$DOWNLOAD_PREFIX"
  --embed-release-notes
  --maximum-versions 0
)
if [ -n "$REPO_PATH" ]; then
  ARGS+=(--link "https://github.com/$REPO_PATH")
fi

if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  ARGS+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
  "$TOOLS/generate_appcast" "${ARGS[@]}"
elif [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$TOOLS/generate_appcast" "${ARGS[@]}" --ed-key-file -
else
  "$TOOLS/generate_appcast" "${ARGS[@]}"
fi

cp -f "$FEED/appcast.xml" "$DIST/appcast.xml"
echo "Wrote $DIST/appcast.xml for version $VERSION"
echo "Upload appcast.xml and $(basename "$NEWEST") to the release, then point SU_FEED_URL at the appcast."
