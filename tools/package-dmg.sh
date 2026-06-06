#!/bin/bash
#
# Packages Info.app into a compressed, draggable DMG with an /Applications
# symlink and a custom volume icon.
#
# Usage: package-dmg.sh <App.app> <out.dmg> [volume-icon.icns]
set -euo pipefail

APP_PATH="${1:?usage: package-dmg.sh <App.app> <out.dmg> [volicon.icns]}"
DMG_OUT="${2:?missing output dmg path}"
VOLICON="${3:-}"
VOL_NAME="Info"

[ -d "$APP_PATH" ] || { echo "error: app not found: $APP_PATH" >&2; exit 1; }

WORK="$(mktemp -d)"
STAGE="$WORK/stage"
MNT="$WORK/mnt"
RW="$WORK/rw.dmg"
mkdir -p "$STAGE"

cleanup() {
  hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "Staging $(basename "$APP_PATH")…"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if [ -n "$VOLICON" ] && [ -f "$VOLICON" ]; then
  cp "$VOLICON" "$STAGE/.VolumeIcon.icns"
fi

echo "Creating read-write image…"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -format UDRW -ov "$RW" >/dev/null

echo "Applying volume icon…"
mkdir -p "$MNT"
hdiutil attach "$RW" -mountpoint "$MNT" -nobrowse -noverify >/dev/null
if [ -n "$VOLICON" ] && command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MNT" || true   # mark volume as having a custom icon
fi
sync
hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach "$MNT" -force >/dev/null 2>&1 || true

echo "Compressing…"
mkdir -p "$(dirname "$DMG_OUT")"
rm -f "$DMG_OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_OUT" >/dev/null

echo "Created $DMG_OUT ($(du -h "$DMG_OUT" | cut -f1))"
