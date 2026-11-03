#!/bin/bash
# Quick script to download only smaller videos (under 500MB) from oldest to newest

echo "Downloading oldest videos under 500 MB..."
echo "This will skip the large multi-GB files and download smaller videos first."
echo ""

python3 scripts/download_oldest_videos.py 10 500

