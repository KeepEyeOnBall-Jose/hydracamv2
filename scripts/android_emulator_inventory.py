#!/usr/bin/env python3
"""Collect Android emulator inventory into a JSON file for reliable inspection."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = REPO_ROOT / "logs" / "android_emulator_inventory.json"


def run_capture(cmd: list[str]) -> dict[str, object]:
    try:
        completed = subprocess.run(
            cmd,
            check=False,
            text=True,
            capture_output=True,
        )
        return {
            "command": cmd,
            "returncode": completed.returncode,
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        }
    except Exception as exc:  # pragma: no cover
        return {
            "command": cmd,
            "error": str(exc),
        }


def main() -> int:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sdk_emulator = shutil.which("emulator")
    adb_path = shutil.which("adb")
    payload = {
        "which": {
            "emulator": sdk_emulator,
            "adb": adb_path,
        },
        "avds": run_capture(["emulator", "-list-avds"]),
        "adb_devices": run_capture(["adb", "devices"]),
    }
    OUTPUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(str(OUTPUT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
