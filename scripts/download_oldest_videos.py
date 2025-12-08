#!/usr/bin/env python3
"""
Download the oldest videos from an attached Android device to the desktop.
"""

import subprocess
import os
import sys
from pathlib import Path
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
        print(f"Error running command: {e}")
        print(f"stderr: {e.stderr}")
        return None

def get_video_files_with_dates():
    """Get all video files from the device with their modification times."""
    print("Scanning device for video files...")

    # Common video directories on Android
    directories = ["/sdcard/DCIM", "/sdcard/Movies", "/sdcard/Download"]

    video_files = []

    for directory in directories:
        # Use ls -lR to get files recursively with timestamps
        cmd = f'adb shell "ls -lR {directory} 2>/dev/null"'
        output = run_command(cmd, shell=True)

        if not output:
            continue

        current_dir = ""
        for line in output.split('\n'):
            # Check if this is a directory line
            if line.endswith(':'):
                current_dir = line[:-1]
            # Check if this is a file line with video extension
            elif any(ext in line.lower() for ext in ['.mp4', '.mov', '.3gp']):
                parts = line.split()
                if len(parts) >= 8:
                    # Extract date, time, and filename
                    date_str = parts[5]
                    time_str = parts[6]
                    filename = parts[7]

                    # Create full path
                    if current_dir:
                        full_path = f"{current_dir}/{filename}"
                    else:
                        full_path = f"{directory}/{filename}"

                    # Parse date for sorting
                    try:
                        datetime_obj = datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M")
                        video_files.append({
                            'path': full_path,
                            'date': datetime_obj,
                            'date_str': f"{date_str} {time_str}",
                            'filename': filename,
                            'size': parts[4]
                        })
                    except ValueError:
                        continue

    # Sort by date (oldest first)
    video_files.sort(key=lambda x: x['date'])

    return video_files

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

def download_videos(video_files, num_videos=5, max_size_mb=None):
    """Download videos to the desktop."""
    if not video_files:
        print("No video files found on device.")
        return

    # Get desktop path
    desktop_path = Path.home() / "Desktop" / "android_videos"
    desktop_path.mkdir(exist_ok=True)

    print(f"\nFound {len(video_files)} total videos on device.")

    # Filter by size if specified
    filtered_files = video_files[:num_videos]
    if max_size_mb:
        max_size_bytes = max_size_mb * 1024 * 1024
        filtered_files = [v for v in video_files if int(v['size']) <= max_size_bytes][:num_videos]
        print(f"Filtering videos under {max_size_mb} MB...")

    print(f"Downloading {len(filtered_files)} oldest videos to: {desktop_path}\n")

    # Download the oldest videos
    downloaded = 0
    skipped = 0
    failed = 0

    for i, video in enumerate(filtered_files):
        print(f"\n[{i+1}/{len(filtered_files)}]")
        print(f"  File: {video['filename']}")
        print(f"  Date: {video['date_str']}")
        print(f"  Size: {format_bytes(video['size'])}")
        print(f"  Path: {video['path']}")

        dest_file = desktop_path / video['filename']

        # Check if file already exists
        if dest_file.exists():
            print(f"  Status: Already exists, skipping...")
            skipped += 1
            continue

        print(f"  Downloading... (this may take a while for large files)")
        cmd = ['adb', 'pull', video['path'], str(dest_file)]
        result = run_command(cmd)

        if result is not None:
            print(f"  Status: ✓ Downloaded successfully")
            downloaded += 1
        else:
            print(f"  Status: ✗ Failed to download")
            failed += 1

    print(f"\n{'='*60}")
    print(f"Download Summary:")
    print(f"  Downloaded: {downloaded}")
    print(f"  Skipped: {skipped}")
    print(f"  Failed: {failed}")
    print(f"  Location: {desktop_path}")
    print(f"{'='*60}\n")

def main():
    # Check if device is connected
    devices_output = run_command(['adb', 'devices'])
    if not devices_output or 'device' not in devices_output:
        print("Error: No Android device connected.")
        print("Please connect a device and try again.")
        sys.exit(1)

    print("Android device detected!")

    # Get video files
    video_files = get_video_files_with_dates()

    if not video_files:
        print("No video files found on device.")
        sys.exit(0)

    # Parse command line arguments
    # Usage: script.py [num_videos] [max_size_mb]
    num_videos = 5
    max_size_mb = None

    if len(sys.argv) > 1:
        try:
            num_videos = int(sys.argv[1])
        except ValueError:
            print(f"Invalid number: {sys.argv[1]}, using default (5)")

    if len(sys.argv) > 2:
        try:
            max_size_mb = int(sys.argv[2])
            print(f"Filtering videos under {max_size_mb} MB")
        except ValueError:
            print(f"Invalid max size: {sys.argv[2]}, ignoring filter")

    # Download videos
    download_videos(video_files, num_videos, max_size_mb)

if __name__ == "__main__":
    main()

