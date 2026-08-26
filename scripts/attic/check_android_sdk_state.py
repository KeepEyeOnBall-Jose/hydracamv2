#!/usr/bin/env python3
"""Capture Android SDK/emulator filesystem state to JSON."""

from __future__ import annotations

import json
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = REPO_ROOT / "logs" / "android_sdk_state.json"
SDK_ROOT = Path("/Users/jose/Library/Android/sdk")
AVD_ROOT = Path.home() / ".android" / "avd"


def safe_list(path: Path) -> dict[str, object]:
    return {
        "exists": path.exists(),
        "items": sorted(item.name for item in path.iterdir()) if path.exists() else [],
    }


def main() -> int:
    payload = {
        "sdkRoot": str(SDK_ROOT),
        "emulatorBinary": {
            "path": str(SDK_ROOT / "emulator" / "emulator"),
            "exists": (SDK_ROOT / "emulator" / "emulator").exists(),
            "executable": os.access(SDK_ROOT / "emulator" / "emulator", os.X_OK),
        },
        "emulatorDir": safe_list(SDK_ROOT / "emulator"),
        "avdRoot": str(AVD_ROOT),
        "avdDir": safe_list(AVD_ROOT),
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(str(OUTPUT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
