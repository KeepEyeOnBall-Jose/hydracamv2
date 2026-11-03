#!/bin/bash
set -e

# Pull most recent camera videos from the currently connected device
# to a Desktop folder, then delete those specific originals.

# 1) Detect a connected device
DEV=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
if [ -z "$DEV" ]; then
  echo "No connected device in 'device' state. Aborting." >&2
  exit 1
fi

echo "Using device: $DEV"

# 2) Destination on Desktop
DEST="$HOME/Desktop/hydracam_device_videos_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DEST"
echo "Desktop destination: $DEST"

# 3) Get most-recent video files under Camera
VIDEO_LIST=$(adb -s "$DEV" shell 'cd /sdcard/DCIM/Camera 2>/dev/null && ls -t 2>/dev/null' \
  | tr -d '\r' \
  | grep -i -E '\\.(mp4|mov|mkv)$' || true)

if [ -z "$VIDEO_LIST" ]; then
  echo "No video files found under /sdcard/DCIM/Camera. Nothing to do."
  exit 0
fi

# Limit to 10 most recent
echo "Selecting up to 10 most recent videos..."
SELECTED=$(printf '%s\n' "$VIDEO_LIST" | head -n 10)

echo "Will transfer:"
printf '  %s\n' $SELECTED

TMPLIST=$(mktemp)
printf '%s\n' $SELECTED > "$TMPLIST"

echo "File list recorded at: $TMPLIST"

# 4) Pull videos
while IFS= read -r NAME; do
  [ -z "$NAME" ] && continue
  echo "Pulling: $NAME"
  adb -s "$DEV" pull "/sdcard/DCIM/Camera/$NAME" "$DEST/" || \
    echo "WARNING: Failed to pull $NAME"
done < "$TMPLIST"

echo
echo "Pulled files in $DEST:"
ls -lah "$DEST" || true

# 5) Delete originals only if present locally
echo
echo "Deleting originals from device for successfully pulled files..."
while IFS= read -r NAME; do
  [ -z "$NAME" ] && continue
  if [ -f "$DEST/$NAME" ]; then
    echo "Deleting on device: $NAME"
    adb -s "$DEV" shell "rm -f \"/sdcard/DCIM/Camera/$NAME\"" || \
      echo "WARNING: Failed to delete $NAME on device"
  else
    echo "Skipping delete for $NAME (not present in $DEST)"
  fi
done < "$TMPLIST"

echo
echo "Local folder size:"
du -sh "$DEST" || true

echo
echo "Device storage info (sdcard/emulated):"
adb -s "$DEV" shell "df -h /sdcard 2>/dev/null || df -h /storage/emulated/0 2>/dev/null || df -h"
