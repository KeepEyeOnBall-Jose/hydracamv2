#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess
import sys


ADB = "/Users/jose/Library/Android/sdk/platform-tools/adb"
SERIALS = [
    "9885e6503930304946",
    "RF8M21J8XRT",
    "RF8M90QE7LX",
]


def run(command: list[str]) -> int:
    print("+ " + " ".join(command), flush=True)
    completed = subprocess.run(command, text=True, check=False)
    return completed.returncode


def capture_screenshot(serial: str, output: pathlib.Path) -> int:
    command = ["ssh", "mba13", ADB, "-s", serial, "exec-out", "screencap", "-p"]
    print("+ " + " ".join(command) + f" > {output}", flush=True)
    with output.open("wb") as handle:
        completed = subprocess.run(command, stdout=handle, stderr=subprocess.PIPE, check=False)
    if completed.stderr:
        sys.stderr.buffer.write(completed.stderr)
    return completed.returncode


def capture_video(serial: str, output: pathlib.Path) -> int:
    remote_video = f"/tmp/hydracam-{serial}-published-foreground.mp4"
    status = run([
        "ssh",
        "mba13",
        "bash",
        "-lc",
        f"set -e; {ADB} -s {serial} shell rm -f /sdcard/hydracam-published-proof.mp4; "
        f"{ADB} -s {serial} shell screenrecord --time-limit 3 /sdcard/hydracam-published-proof.mp4; "
        f"{ADB} -s {serial} pull /sdcard/hydracam-published-proof.mp4 {remote_video}",
    ])
    if status != 0:
        return status
    return run(["scp", f"mba13:{remote_video}", str(output)])


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: capture_android_foreground_media.py <evidence-run-dir>", file=sys.stderr)
        return 2

    run_dir = pathlib.Path(sys.argv[1]).resolve()
    screenshot_dir = run_dir / "screenshots"
    video_dir = run_dir / "video"
    screenshot_dir.mkdir(parents=True, exist_ok=True)
    video_dir.mkdir(parents=True, exist_ok=True)

    status = 0
    for serial in SERIALS:
        status = capture_screenshot(serial, screenshot_dir / f"{serial}-published-foreground.png") or status
        status = capture_video(serial, video_dir / f"{serial}-published-foreground.mp4") or status

    return status


if __name__ == "__main__":
    raise SystemExit(main())
