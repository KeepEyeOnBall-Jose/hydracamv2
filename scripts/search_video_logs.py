#!/usr/bin/env python3
"""
Search orchestrator logs for video-related events.
"""

import json
from pathlib import Path

log_file = Path("automation_runs/20251120_222427-quad_demo/emulator-5554/logs.json")

with open(log_file) as f:
    data = json.load(f)
    logs = data.get("logs", [])

print(f"Total logs: {len(logs)}\n")

# Search for video/recording related logs
keywords = ["video", "recording", "record", "mp4", "camera", "capture"]

matches = []
for log in logs:
    msg = log.get("message", "").lower()
    if any(kw in msg for kw in keywords):
        matches.append(log)

print(f"Found {len(matches)} video/recording related log entries:\n")

for i, log in enumerate(matches, 1):
    timestamp = log.get("timestamp", "")
    message = log.get("message", "")
    function = log.get("function", "")
    file = log.get("file", "")

    location = f"{file}::{function}" if file and function else (file or function or "")

    print(f"[{i}] {timestamp}")
    if location:
        print(f"    Location: {location}")
    print(f"    {message}")
    print()
