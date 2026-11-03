#!/bin/bash
# Pull session media from device

SESSION_GUID="517d17d5-1293-4276-bafd-135b1fed4749"
SERIAL="emulator-5554"
APP_PKG="com.amaia23.hydracam"
SESSION_DIR="/data/data/${APP_PKG}/app_flutter/session_${SESSION_GUID}"
LOCAL_DIR="automation_runs/20251120_222427-quad_demo/session_media"

mkdir -p "$LOCAL_DIR"

echo "=== Pulling session media from $SERIAL ==="

# Get list of media files
FILES=$(adb -s "$SERIAL" shell "run-as $APP_PKG ls $SESSION_DIR/ 2>/dev/null | grep -E '\.(jpg|mp4)$'")

for FILE in $FILES; do
    BASENAME=$(basename "$FILE")
    echo "Pulling $BASENAME..."
    
    # Use content provider approach - copy to cache first
    CACHE_PATH="/data/data/${APP_PKG}/cache/${BASENAME}"
    adb -s "$SERIAL" shell "run-as $APP_PKG cp $FILE $CACHE_PATH"
    adb -s "$SERIAL" shell "run-as $APP_PKG cat $CACHE_PATH" > "${LOCAL_DIR}/${BASENAME}"
    adb -s "$SERIAL" shell "run-as $APP_PKG rm $CACHE_PATH"
    
    if [ -f "${LOCAL_DIR}/${BASENAME}" ]; then
        SIZE=$(stat -f%z "${LOCAL_DIR}/${BASENAME}" 2>/dev/null || stat -c%s "${LOCAL_DIR}/${BASENAME}" 2>/dev/null)
        echo "  ✓ Pulled $BASENAME ($SIZE bytes)"
    else
        echo "  ✗ Failed to pull $BASENAME"
    fi
done

echo ""
echo "=== Media files in $LOCAL_DIR ==="
ls -lh "$LOCAL_DIR"
