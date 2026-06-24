#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
from pathlib import Path


RUN_DIR = Path(
    "logs/verification-runs/"
    "20260622-1426-master-session-controls-compact-layout"
)
SERIALS = {
    "9885e6503930304946": (360, 640),
    "RF8M90QE7LX": (674, 360),
}
OVERFLOW_MARKERS = (
    "RenderFlex overflowed",
    "BOTTOM OVERFLOWED",
    "RIGHT OVERFLOWED",
)


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        signature = handle.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            raise AssertionError(f"{path} is not a PNG")
        length = struct.unpack(">I", handle.read(4))[0]
        chunk_type = handle.read(4)
        if chunk_type != b"IHDR" or length < 8:
            raise AssertionError(f"{path} is missing PNG IHDR")
        width, height = struct.unpack(">II", handle.read(8))
        return width, height


def require_file(path: Path) -> Path:
    if not path.is_file():
        raise AssertionError(f"Missing {path}")
    if path.stat().st_size <= 0:
        raise AssertionError(f"Empty file {path}")
    return path


def main() -> int:
    for serial, expected_dimensions in SERIALS.items():
        install_log = require_file(RUN_DIR / "device-logs/mba13" / f"install-{serial}.txt")
        if "Success" not in install_log.read_text(encoding="utf-8"):
            raise AssertionError(f"Install did not pass for {serial}")

        health = json.loads(
            require_file(
                RUN_DIR / "device-logs/mba13" / f"health-{serial}.json"
            ).read_text(encoding="utf-8")
        )
        if health.get("automationTargetId") != serial:
            raise AssertionError(f"Bridge target mismatch for {serial}: {health}")
        commands = set(health.get("commands", []))
        if "capture_screenshot" not in commands:
            raise AssertionError(f"capture_screenshot missing for {serial}: {health}")

        response = json.loads(
            require_file(
                RUN_DIR / "device-logs/mba13" / f"capture-response-{serial}.json"
            ).read_text(encoding="utf-8")
        )
        result = response.get("result", {})
        if (result.get("width"), result.get("height")) != expected_dimensions:
            raise AssertionError(f"Unexpected capture dimensions for {serial}: {result}")

        screenshot = require_file(
            RUN_DIR / "screenshots" / f"master-compact-{serial}.png"
        )
        if png_dimensions(screenshot) != expected_dimensions:
            raise AssertionError(f"Unexpected PNG dimensions for {serial}")
        require_file(RUN_DIR / "screenshots" / f"system-master-compact-{serial}.png")
        require_file(RUN_DIR / "video" / f"master-compact-{serial}.mp4")

        logcat = require_file(RUN_DIR / "device-logs/mba13" / f"logcat-{serial}.txt")
        log_text = logcat.read_text(encoding="utf-8", errors="replace")
        for marker in OVERFLOW_MARKERS:
            if marker in log_text:
                raise AssertionError(f"Found overflow marker {marker!r} for {serial}")

    print("Validated MBA13 Master UI evidence for both attached Android devices.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
