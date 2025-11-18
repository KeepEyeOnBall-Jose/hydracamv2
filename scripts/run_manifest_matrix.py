#!/usr/bin/env python3
"""Run the quad_smoke manifest across 1-5 devices with rotating masters."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List

REPO_ROOT = Path(__file__).resolve().parents[1]
ORCHESTRATOR = REPO_ROOT / "scripts" / "multi_device_orchestrator.py"
MANIFEST = REPO_ROOT / "automation_scenarios" / "quad_smoke.json"
PACKAGE_NAME = "com.amaia23.hydracam"
MAIN_ACTIVITY = "com.amaia23.hydracam/.MainActivity"
APP_STABILIZE_SECONDS = 15


@dataclass(frozen=True)
class RunConfig:
    scenario: str
    devices: List[str]


RUN_MATRIX: List[RunConfig] = [
    RunConfig("devices_1_master_5554", ["emulator-5554"]),
    RunConfig("devices_2_master_5556", ["emulator-5556", "emulator-5554"]),
    RunConfig(
        "devices_3_master_5558",
        ["emulator-5558", "emulator-5554", "emulator-5556"],
    ),
    RunConfig(
        "devices_4_master_5560",
        [
            "emulator-5560",
            "emulator-5554",
            "emulator-5556",
            "emulator-5558",
        ],
    ),
    RunConfig(
        "devices_5_master_5562",
        [
            "emulator-5562",
            "emulator-5554",
            "emulator-5556",
            "emulator-5558",
            "emulator-5560",
        ],
    ),
]

ROLE_BY_POSITION = {
    0: "master",
}


def _run(cmd: List[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    """Run a command and stream output unless capture=True."""
    if capture:
        return subprocess.run(
            cmd,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    return subprocess.run(cmd, check=True, text=True)


def _prepare_device(serial: str, role: str) -> None:
    """Force-stop HydraCam and relaunch it with automation extras."""
    print(f"\n→ Preparing {serial} as {role}...")
    _disable_audio(serial)
    _run(["adb", "-s", serial, "shell", "am", "force-stop", PACKAGE_NAME])
    launch_cmd = [
        "adb",
        "-s",
        serial,
        "shell",
        "am",
        "start",
        "-n",
        MAIN_ACTIVITY,
        "--ez",
        "HYDRACAM_AUTOMATION",
        "true",
        "--es",
        "role",
        role,
    ]
    if role == "slave":
        launch_cmd.extend(["--ez", "forceSlaveMode", "true"])
    _run(launch_cmd)


def _serials_arg(devices: List[str]) -> str:
    """Build the --serials argument value."""
    parts: List[str] = []
    for index, serial in enumerate(devices):
        role = ROLE_BY_POSITION.get(index, "slave")
        parts.append(f"{serial}:{role}")
    return ",".join(parts)


def _disable_audio(serial: str) -> None:
    """Disable microphone/audio capture to avoid hijacking host audio."""
    appops = [
        "RECORD_AUDIO",
        "CAPTURE_AUDIO_OUTPUT",
        "CAPTURE_AUDIO_HOTWORD",
    ]
    for op in appops:
        try:
            _run(
                [
                    "adb",
                    "-s",
                    serial,
                    "shell",
                    "cmd",
                    "appops",
                    "set",
                    PACKAGE_NAME,
                    op,
                    "ignore",
                ],
                capture=True,
            )
        except subprocess.CalledProcessError:
            print(f"Warning: failed to disable {op} for {serial}")


def run_matrix(selected: Iterable[str] | None = None) -> None:
    """Run the orchestrator for each configured scenario."""
    scenarios = {cfg.scenario: cfg for cfg in RUN_MATRIX}
    queue: List[RunConfig]
    if selected:
        queue = []
        for name in selected:
            if name not in scenarios:
                valid = ", ".join(scenarios)
                raise SystemExit(f"Unknown scenario '{name}'. Valid: {valid}")
            queue.append(scenarios[name])
    else:
        queue = RUN_MATRIX

    for cfg in queue:
        print("\n========================================")
        print(f"Running scenario: {cfg.scenario}")
        print("Devices:", ", ".join(cfg.devices))
        print("========================================\n")

        for idx, serial in enumerate(cfg.devices):
            role = ROLE_BY_POSITION.get(idx, "slave")
            _prepare_device(serial, role)

        print(
            "Waiting "
            f"{APP_STABILIZE_SECONDS}s for apps to reach the right screens..."
        )
        time.sleep(APP_STABILIZE_SECONDS)

        serials_value = _serials_arg(cfg.devices)
        cmd = [
            sys.executable,
            str(ORCHESTRATOR),
            "--serials",
            serials_value,
            "--manifest",
            str(MANIFEST),
            "--scenario",
            cfg.scenario,
        ]
        print("Invoking orchestrator:", " ".join(cmd))
        _run(cmd)

        print(f"Scenario {cfg.scenario} complete.\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "scenarios",
        nargs="*",
        help="Optional subset of scenario names to run (defaults to all).",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run_matrix(args.scenarios or None)
