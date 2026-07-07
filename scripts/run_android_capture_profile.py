#!/usr/bin/env python3
"""Run one Android device through a local lens/profile capture smoke."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path
from typing import Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APK = REPO_ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"
DEFAULT_MANIFEST = (
    REPO_ROOT / "automation_scenarios" / "single_device_capture_profile.json"
)
ORCHESTRATOR = REPO_ROOT / "scripts" / "multi_device_orchestrator.py"
PACKAGE_NAME = "com.amaia23.hydracam"
MAIN_ACTIVITY = f"{PACKAGE_NAME}/.MainActivity"
DEFAULT_PERMISSIONS = (
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.ACCESS_MEDIA_LOCATION",
)


def run(
    command: Sequence[str],
    *,
    check: bool = True,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    print("+ " + " ".join(command), flush=True)
    return subprocess.run(
        list(command),
        cwd=REPO_ROOT,
        check=check,
        text=True,
        timeout=timeout,
    )


def validated_dart_defines(args: argparse.Namespace) -> list[str]:
    defines = list(getattr(args, "dart_define", []) or [])
    invalid = [
        define for define in defines if "=" not in define or define.startswith("=")
    ]
    if invalid:
        raise ValueError(
            "--dart-define values must use KEY=VALUE: " + ", ".join(invalid)
        )
    return defines


def build_apk(args: argparse.Namespace) -> Path:
    apk = Path(args.apk)
    if not args.build:
        if not apk.exists():
            raise FileNotFoundError(f"APK not found: {apk}")
        return apk
    command = [
        "flutter",
        "build",
        "apk",
        "--debug",
        "--dart-define=HYDRACAM_AUTOMATION=true",
    ]
    command.extend(
        f"--dart-define={define}" for define in validated_dart_defines(args)
    )
    run(command, timeout=args.build_timeout)
    if not apk.exists():
        raise FileNotFoundError(f"Flutter build did not produce APK: {apk}")
    return apk


def grant_permissions(serial: str) -> None:
    for permission in DEFAULT_PERMISSIONS:
        run(
            ["adb", "-s", serial, "shell", "pm", "grant", PACKAGE_NAME, permission],
            check=False,
        )


def launch_app(serial: str) -> None:
    run(["adb", "-s", serial, "shell", "am", "force-stop", PACKAGE_NAME])
    run(
        [
            "adb",
            "-s",
            serial,
            "shell",
            "am",
            "start",
            "-n",
            MAIN_ACTIVITY,
            "--es",
            "role",
            "master",
        ]
    )


def run_capture(args: argparse.Namespace) -> int:
    apk = build_apk(args)
    if not args.skip_install:
        run(["adb", "-s", args.serial, "install", "-r", str(apk)])

    grant_permissions(args.serial)
    launch_app(args.serial)
    time.sleep(args.stabilize_seconds)

    scenario = args.scenario or f"{args.serial}-{args.profile}-{args.lens}"
    run(
        [
            sys.executable,
            str(ORCHESTRATOR),
            "--serials",
            f"{args.serial}:master",
            "--manifest",
            str(args.manifest),
            "--scenario",
            scenario,
            "--output-dir",
            str(args.output_dir),
            "--port-base",
            str(args.port_base),
            "--context",
            f"cameraLensPreference={args.lens}",
            "--context",
            f"videoCaptureProfile={args.profile}",
        ]
    )
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--lens", default="autoBack")
    parser.add_argument("--profile", default="standard1080p30")
    parser.add_argument("--scenario")
    parser.add_argument("--apk", type=Path, default=DEFAULT_APK)
    parser.add_argument(
        "--build",
        action="store_true",
        help="Build the debug APK before installing.",
    )
    parser.add_argument("--build-timeout", type=float, default=300)
    parser.add_argument(
        "--dart-define",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help=(
            "Additional Flutter dart define for --build. Repeat for "
            "bridge-mode flags such as HYDRACAM_USE_MEDIA_TIMELINE_BRIDGE=true."
        ),
    )
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=REPO_ROOT / "logs" / "verification-runs",
    )
    parser.add_argument("--skip-install", action="store_true")
    parser.add_argument("--stabilize-seconds", type=float, default=8)
    parser.add_argument("--port-base", type=int, default=6100)
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(run_capture(parse_args(sys.argv[1:])))
