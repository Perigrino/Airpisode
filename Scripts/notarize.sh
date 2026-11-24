#!/usr/bin/env bash
# Submits a signed DMG to Apple's notary service and staples the ticket, so Gatekeeper
# opens the downloaded app without a warning. Requires a Developer ID build
# (Scripts/build-dmg.sh with AIRPISODE_SIGN_IDENTITY set).
#
# Credentials, either:
#   NOTARY_PROFILE       a profile stored with `xcrun notarytool store-credentials`
# or all three:
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   (an app-specific password)
set -euo pipefail

DMG="${1:?Usage: Scripts/notarize.sh <path-to-dmg>}"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  AUTH=(--keychain-profile "$NOTARY_PROFILE")
else
  : "${APPLE_ID:?Set NOTARY_PROFILE, or APPLE_ID and APPLE_TEAM_ID and APPLE_APP_PASSWORD}"
  : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
  : "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD (an app-specific password, not your Apple ID password)}"
  AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
fi

xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "Notarized and stapled $DMG"
