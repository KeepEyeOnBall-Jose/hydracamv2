#!/bin/bash
# Upload videos from Android device to Mac FTP server using curl via ADB

# Get FTP server details
if [ -z "$1" ]; then
    echo "Usage: $0 <FTP_SERVER_IP> [max_files]"
    echo "Example: $0 192.168.1.100 5"
    exit 1
fi

FTP_SERVER="$1"
FTP_PORT="${2:-2121}"
MAX_FILES="${3:-5}"

echo "======================================"
echo "Android to Mac FTP Transfer"
echo "======================================"
echo "FTP Server: $FTP_SERVER:$FTP_PORT"
echo "Max Files: $MAX_FILES"
echo ""

# Check if device is connected
if ! adb devices | grep -q "device$"; then
    echo "❌ No Android device connected"
    exit 1
fi

echo "✅ Android device connected"
echo ""
echo "Finding oldest video files..."
echo ""

# Create a script on the device to find and upload videos
adb shell "cat > /sdcard/ftp_upload.sh << 'EOFSCRIPT'
#!/system/bin/sh

FTP_SERVER=\"\$1\"
FTP_PORT=\"\$2\"
MAX_FILES=\"\$3\"

echo \"Scanning for video files...\"

# Find all video files sorted by date
find /sdcard/DCIM /sdcard/Movies /sdcard/Download -type f \\
    \( -name '*.mp4' -o -name '*.MP4' -o -name '*.mov' -o -name '*.MOV' \\
       -o -name '*.3gp' -o -name '*.3GP' \) 2>/dev/null | while read file; do
    stat -c \"%Y %n\" \"\$file\" 2>/dev/null || stat -f \"%m %N\" \"\$file\" 2>/dev/null
done | sort -n | head -n \"\$MAX_FILES\" | while read timestamp filepath; do
    filename=\$(basename \"\$filepath\")
    filesize=\$(stat -c %s \"\$filepath\" 2>/dev/null || stat -f %z \"\$filepath\" 2>/dev/null)

    # Convert size to human readable
    if [ \$filesize -gt 1073741824 ]; then
        size_display=\"\$((\$filesize / 1073741824)) GB\"
    elif [ \$filesize -gt 1048576 ]; then
        size_display=\"\$((\$filesize / 1048576)) MB\"
    else
        size_display=\"\$((\$filesize / 1024)) KB\"
    fi

    echo \"\"
    echo \"Uploading: \$filename (\$size_display)\"
    echo \"From: \$filepath\"

    # Upload using curl
    curl -T \"\$filepath\" \"ftp://\$FTP_SERVER:\$FTP_PORT/\$filename\" --user anonymous: -# 2>&1

    if [ \$? -eq 0 ]; then
        echo \"✓ Upload successful\"
    else
        echo \"✗ Upload failed\"
    fi
done

echo \"\"
echo \"Transfer complete!\"
EOFSCRIPT"

# Make script executable
adb shell "chmod +x /sdcard/ftp_upload.sh"

echo "Starting upload process..."
echo ""

# Execute the upload script on device
adb shell "sh /sdcard/ftp_upload.sh '$FTP_SERVER' '$FTP_PORT' '$MAX_FILES'"

# Cleanup
adb shell "rm /sdcard/ftp_upload.sh"

echo ""
echo "======================================"
echo "Transfer completed!"
echo "Check ~/Desktop/android_videos/"
echo "======================================"

