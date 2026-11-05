#!/bin/bash
# Render Resources/AppIcon.svg into the app's PNG and all native ICNS sizes.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_WORK="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK"' EXIT
ICON_SET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICON_SET"
# The native grid icon has its own editable source and includes the macOS tile margin.
# The older website mark contains a mouse outline and cannot reproduce this icon.
magick -background none -density 144 "$REPO_ROOT/Resources/AppIcon.svg" \
  -resize 1024x1024 -strip "$ICON_WORK/master.png"
for SIZE in 16 32 128 256 512; do
  # Exclude export timestamps so rebuilding unchanged artwork leaves no diff.
  magick "$ICON_WORK/master.png" -resize "${SIZE}x${SIZE}" -strip "$ICON_SET/icon_${SIZE}x${SIZE}.png"
  DOUBLE=$((SIZE * 2))
  magick "$ICON_WORK/master.png" -resize "${DOUBLE}x${DOUBLE}" -strip "$ICON_SET/icon_${SIZE}x${SIZE}@2x.png"
done
iconutil -c icns "$ICON_SET" -o "$REPO_ROOT/Resources/AppIcon.icns"
cp "$ICON_WORK/master.png" "$REPO_ROOT/Resources/AppIcon.png"
