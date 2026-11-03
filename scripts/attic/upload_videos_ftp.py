#!/usr/bin/env python3
"""
Upload oldest videos from Android device to Mac via FTP using curl.
This script finds videos on the device and uploads them via FTP.
"""

import subprocess
import sys
from datetime import datetime

def run_command(cmd, shell=False):
    """Run a shell command and return output."""
    try:
        result = subprocess.run(
            cmd,
            shell=shell,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error: {e.stderr}")
        return None

def format_bytes(bytes_val):
    """Format bytes to human readable format."""
    try:
        bytes_val = int(bytes_val)
        for unit in ['B', 'KB', 'MB', 'GB']:
            if bytes_val < 1024.0:
                return f"{bytes_val:.2f} {unit}"
            bytes_val /= 1024.0
        return f"{bytes_val:.2f} TB"
    except:
        return str(bytes_val)

def get_video_files():
    """Get video files from Android device sorted by date."""
    print("📱 Scanning Android device for videos...")

    directories = ["/sdcard/DCIM", "/sdcard/Movies", "/sdcard/Download"]
    video_files = []

    for directory in directories:
        cmd = f'adb shell "ls -lR {directory} 2>/dev/null"'
        output = run_command(cmd, shell=True)

        if not output:
            continue

        current_dir = ""
        for line in output.split('\n'):
            if line.endswith(':'):
                current_dir = line[:-1]
            elif any(ext in line.lower() for ext in ['.mp4', '.mov', '.3gp']):
                parts = line.split()
                if len(parts) >= 8:
                    date_str = parts[5]
                    time_str = parts[6]
                    filename = parts[7]
                    size = parts[4]

                    if current_dir:
                        full_path = f"{current_dir}/{filename}"
                    else:
                        full_path = f"{directory}/{filename}"

                    try:
                        datetime_obj = datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M")
                        video_files.append({
                            'path': full_path,
                            'date': datetime_obj,
                            'filename': filename,
                            'size': size
                        })
                    except ValueError:
                        continue

    video_files.sort(key=lambda x: x['date'])
    return video_files

def upload_via_ftp(video_files, ftp_host, ftp_port=2121, max_files=5):
    """Upload videos to FTP server using curl on Android device."""

    if not video_files:
        print("❌ No videos found")
        return

    files_to_upload = video_files[:max_files]

    print(f"\n{'='*70}")
    print(f"📤 Uploading {len(files_to_upload)} oldest videos to FTP server")
    print(f"{'='*70}\n")

    for i, video in enumerate(files_to_upload, 1):
        print(f"[{i}/{len(files_to_upload)}] {video['filename']}")
        print(f"  Size: {format_bytes(video['size'])}")
        print(f"  Date: {video['date'].strftime('%Y-%m-%d %H:%M')}")
        print(f"  Uploading... ", end='', flush=True)

        # Use curl on Android to upload to FTP
        ftp_url = f"ftp://{ftp_host}:{ftp_port}/{video['filename']}"
        cmd = f'adb shell "curl -T \\"{video["path"]}\\" \\"{ftp_url}\\" --user anonymous: 2>&1"'

        result = run_command(cmd, shell=True)

        if result is not None and "100" in result:
            print("✅ Success")
        else:
            print("❌ Failed")
            if result:
                print(f"     Error: {result[:100]}")
        print()

    print(f"{'='*70}")
    print("✅ Upload complete!")
    print(f"{'='*70}\n")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 upload_videos_ftp.py <FTP_SERVER_IP> [max_files] [ftp_port]")
        print("Example: python3 upload_videos_ftp.py 192.168.1.100 5 2121")
        sys.exit(1)

    ftp_host = sys.argv[1]
    max_files = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    ftp_port = int(sys.argv[3]) if len(sys.argv) > 3 else 2121

    # Check device
    devices = run_command(['adb', 'devices'])
    if not devices or 'device' not in devices:
        print("❌ No Android device connected")
        sys.exit(1)

    print("✅ Android device connected")

    # Get videos
    video_files = get_video_files()

    if not video_files:
        print("❌ No videos found on device")
        sys.exit(1)

    print(f"✅ Found {len(video_files)} videos")

    # Upload
    upload_via_ftp(video_files, ftp_host, ftp_port, max_files)

if __name__ == "__main__":
    main()
