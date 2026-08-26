#!/usr/bin/env python3
"""Search logs for stop recording and video save events."""

import json
from pathlib import Path

log_file = Path("automation_runs/20251120_222427-quad_demo/emulator-5554/logs.json")

with open(log_file, encoding='utf-8') as f:
    data = json.load(f)
    logs = data.get("logs", [])

keywords = ['stop', 'saved', 'video file', 'finalized', 'complete', 
            'ended', 'finished', 'upload', 'queue']

matches = [log for log in logs if any(kw in log.get('message', '').lower() for kw in keywords)]

print(f"Found {len(matches)} matches:\n")

for log in matches[-30:]:  # Last 30 matches
    print(f"{log['timestamp']}: {log['message']}")
