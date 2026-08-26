#!/usr/bin/env python3
"""
List all videos on the connected Android device sorted by date.
"""

import subprocess
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
        return None

def format_bytes(bytes_val):
    """Format bytes to human readable format."""
    try:
        bytes_val = int(bytes_val)
        for unit in ['B', 'KB', 'MB', 'GB']:
            if bytes_val < 1024.0:
                return f"{bytes_val:7.2f} {unit}"
            bytes_val /= 1024.0
        return f"{bytes_val:7.2f} TB"
    except:
        return str(bytes_val)

def get_video_files_with_dates():
    """Get all video files from the device with their modification times."""
    print("Scanning device for video files...")

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
                            'date_str': f"{date_str} {time_str}",
                            'filename': filename,
                            'size': size
                        })
                    except ValueError:
                        continue

    video_files.sort(key=lambda x: x['date'])
    return video_files

def main():
    # Check if device is connected
    devices_output = run_command(['adb', 'devices'])
    if not devices_output or 'device' not in devices_output:
        print("Error: No Android device connected.")
        return

    print("Android device detected!\n")

    video_files = get_video_files_with_dates()

    if not video_files:
        print("No video files found on device.")
        return

    print(f"\n{'='*80}")
    print(f"Found {len(video_files)} videos on device (sorted by date, oldest first):")
    print(f"{'='*80}\n")
    print(f"{'#':>3}  {'Date & Time':<16}  {'Size':>12}  {'Filename':<40}")
    print(f"{'-'*80}")

    for i, video in enumerate(video_files, 1):
        print(f"{i:>3}  {video['date_str']:<16}  {format_bytes(video['size']):>12}  {video['filename']:<40}")

    print(f"\n{'='*80}")
    print(f"To download oldest videos:")
    print(f"  python3 scripts/download_oldest_videos.py [num_videos] [max_size_mb]")
    print(f"\nExamples:")
    print(f"  python3 scripts/download_oldest_videos.py 10        # Download oldest 10 videos")
    print(f"  python3 scripts/download_oldest_videos.py 20 500    # Download oldest 20 videos under 500 MB")
    print(f"{'='*80}\n")

if __name__ == "__main__":
    main()

