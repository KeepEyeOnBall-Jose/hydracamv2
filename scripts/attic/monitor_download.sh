#!/bin/bash
# Monitor the progress of video downloads

DOWNLOAD_DIR="$HOME/Desktop/android_videos"

echo "==================================="
echo "Android Video Download Monitor"
echo "==================================="
echo ""

if [ ! -d "$DOWNLOAD_DIR" ]; then
    echo "❌ Download directory not found: $DOWNLOAD_DIR"
    exit 1
fi

echo "📁 Download Location: $DOWNLOAD_DIR"
echo ""

# Check if adb pull is running
if ps aux | grep "adb pull" | grep -v grep > /dev/null; then
    echo "✅ Download is ACTIVE"
    echo ""

    # Get the file being downloaded
    CURRENT_FILE=$(ps aux | grep "adb pull" | grep -v grep | awk '{print $NF}')
    FILENAME=$(basename "$CURRENT_FILE")

    echo "📥 Currently downloading: $FILENAME"

    if [ -f "$CURRENT_FILE" ]; then
        CURRENT_SIZE=$(ls -lh "$CURRENT_FILE" | awk '{print $5}')
        echo "   Current size: $CURRENT_SIZE"
    fi
else
    echo "⏸️  No active download"
fi

echo ""
echo "-----------------------------------"
echo "Files in download directory:"
echo "-----------------------------------"

if [ -z "$(ls -A $DOWNLOAD_DIR 2>/dev/null)" ]; then
    echo "  (empty)"
else
    ls -lh "$DOWNLOAD_DIR" | tail -n +2 | awk '{printf "  %-40s %10s\n", $9, $5}'
fi

echo ""
echo "-----------------------------------"
echo "Total size downloaded:"
du -sh "$DOWNLOAD_DIR" | awk '{print "  " $1}'
echo "-----------------------------------"

