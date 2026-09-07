#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_WORK="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK"' EXIT
ICON_SET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICON_SET"
# Reuse the public twelve-button mark; the transparent margin matches macOS app tiles.
magick -background none -density 1152 "$REPO_ROOT/docs/agentic-mouse-mark.svg" \
  -resize 896x896 -gravity center -extent 1024x1024 "$ICON_WORK/master.png"
for SIZE in 16 32 128 256 512; do
  magick "$ICON_WORK/master.png" -resize "${SIZE}x${SIZE}" "$ICON_SET/icon_${SIZE}x${SIZE}.png"
  DOUBLE=$((SIZE * 2))
  magick "$ICON_WORK/master.png" -resize "${DOUBLE}x${DOUBLE}" "$ICON_SET/icon_${SIZE}x${SIZE}@2x.png"
done
iconutil -c icns "$ICON_SET" -o "$REPO_ROOT/Resources/AppIcon.icns"
cp "$ICON_WORK/master.png" "$REPO_ROOT/Resources/AppIcon.png"
