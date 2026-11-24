#!/usr/bin/env bash
# Downloads the Sparkle release tools (generate_appcast, sign_update, generate_keys).
# They are not shipped inside the app; they only run on the machine that publishes a
# release. Cached in .build/sparkle-tools, which git ignores.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/.build/sparkle-tools"

# Keep the tools on the same version as the framework the app links against.
VERSION="$(sed -n 's/^[[:space:]]*exactVersion:[[:space:]]*"\([0-9.]*\)".*/\1/p' "$ROOT/project.yml" | head -1)"
[ -n "$VERSION" ] || { echo "Could not read the Sparkle version from project.yml" >&2; exit 1; }

if [ -x "$DEST/bin/generate_appcast" ]; then
  echo "Sparkle $VERSION tools already present in $DEST/bin"
  exit 0
fi

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL -o "$TMP/Sparkle-$VERSION.tar.xz" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
tar -xJf "$TMP/Sparkle-$VERSION.tar.xz" -C "$DEST"

echo "Installed Sparkle $VERSION tools in $DEST/bin"
