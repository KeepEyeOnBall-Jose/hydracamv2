#!/usr/bin/env python3
"""Start N Android emulators and verify they finish Android boot.

Dry-run by default; pass `--start` to actually launch emulators.
"""

# Make the project root importable so this script can be run directly
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import argparse
import subprocess
import time
from typing import List

from scripts.emulator_manager import (
    EmulatorLaunchSpec,
    EmulatorManager,
    hydra_cluster_specs,
    parse_emulator_spec,
)


def parse_args(argv: List[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Boot N Android emulators and wait until they appear",
    )
    p.add_argument(
        "-n",
        "--count",
        type=int,
        default=1,
        help="Number of emulators to start",
    )
    p.add_argument(
        "--avd-base",
        type=str,
        default="Pixel_7",
        help="Base AVD name to use when booting emulators",
    )
    p.add_argument(
        "--start-port",
        type=int,
        default=5554,
        help="Starting port for first emulator (increments by 2)",
    )
    p.add_argument(
        "--shared-net-id-start",
        type=int,
        help="Starting shared network id (assigns one secondary 10.1.2.x IP per emulator)",
    )
    p.add_argument(
        "--spec",
        action="append",
        default=[],
        metavar="AVD:PORT[:SHARED_NET_ID]",
        help="Explicit emulator launch spec; may be passed multiple times",
    )
    p.add_argument(
        "--hydra-cluster",
        action="store_true",
        help="Launch Hydra_Master_API34 + three Hydra_Slave* AVDs with shared net ids",
    )
    p.add_argument(
        "--timeout",
        type=int,
        default=120,
        help="Seconds to wait for emulators to finish Android boot",
    )
    p.add_argument(
        "--interval",
        type=float,
        default=2.0,
        help="Polling interval in seconds",
    )
    p.add_argument(
        "--start",
        action="store_true",
        help="Actually start emulators (otherwise dry-run)",
    )
    p.add_argument(
        "--terminal-app",
        action="store_true",
        help=(
            "Launch emulators through Terminal.app instead of detached nohup. "
            "This is more reliable in Codex/background automation contexts."
        ),
    )
    p.add_argument(
        "--no-window",
        action="store_true",
        help="Pass -no-window to the emulator.",
    )
    p.add_argument(
        "--no-audio",
        action="store_true",
        help="Pass -no-audio to the emulator.",
    )
    p.add_argument(
        "--no-boot-anim",
        action="store_true",
        help="Pass -no-boot-anim to the emulator.",
    )
    p.add_argument(
        "--wipe-data",
        action="store_true",
        help="Pass -wipe-data to start from a clean AVD data image.",
    )
    p.add_argument(
        "--adb-visible-only",
        action="store_true",
        help="Only require ADB visibility, preserving the old weaker check.",
    )
    return p.parse_args(argv)


def resolve_launch_specs(
    args: argparse.Namespace, manager: EmulatorManager
) -> List[EmulatorLaunchSpec]:
    if args.hydra_cluster:
        return hydra_cluster_specs(
            start_port=args.start_port,
            start_shared_net_id=(
                args.shared_net_id_start
                if args.shared_net_id_start is not None
                else 11
            ),
        )

    if args.spec:
        return [parse_emulator_spec(spec_text) for spec_text in args.spec]

    return manager.build_n_emulator_specs(
        args.avd_base,
        args.count,
        start_port=args.start_port,
        shared_net_id_start=args.shared_net_id_start,
    )


def _adb_shell_value(device_id: str, *command: str, timeout: float = 5) -> str:
    try:
        result = subprocess.run(
            ["adb", "-s", device_id, "shell", *command],
            check=False,
            capture_output=True,
            encoding="utf-8",
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def _boot_completed(device_id: str) -> bool:
    return _adb_shell_value(device_id, "getprop", "sys.boot_completed") == "1"


def wait_for_emulators(
    manager: EmulatorManager,
    specs: List[EmulatorLaunchSpec],
    timeout: int,
    interval: float,
    *,
    adb_visible_only: bool = False,
) -> List[str]:
    deadline = time.time() + timeout
    expected_ids = [f"emulator-{spec.port}" for spec in specs]
    while time.time() < deadline:
        visible_ids = set(manager.list_android_emulators())
        ready = []
        for device_id in expected_ids:
            if device_id not in visible_ids:
                continue
            if adb_visible_only or _boot_completed(device_id):
                ready.append(device_id)
        if len(ready) == len(expected_ids):
            return ready
        time.sleep(interval)
    visible_ids = set(manager.list_android_emulators())
    return [
        device_id
        for device_id in expected_ids
        if device_id in visible_ids
        and (adb_visible_only or _boot_completed(device_id))
    ]


def main(argv: List[str] | None = None) -> int:
    args = parse_args(argv)
    manager = EmulatorManager()
    specs = resolve_launch_specs(args, manager)

    if not args.start:
        print(f"[boot] Dry-run: would start {len(specs)} emulator(s):")
        for spec in specs:
            shared_ip = (
                f" secondary IP 10.1.2.{spec.shared_net_id}"
                if spec.shared_net_id is not None
                else ""
            )
            read_only = " read-only" if spec.read_only else ""
            print(
                f"  - {spec.avd_name} on emulator-{spec.port}"
                f"{read_only}{shared_ip}"
            )
        print("[boot] To actually start emulators, pass --start")
        return 0

    print(f"[boot] Starting {len(specs)} emulator(s)")
    manager.start_emulator_specs(
        specs,
        terminal_app=args.terminal_app,
        no_window=args.no_window,
        no_audio=args.no_audio,
        no_boot_anim=args.no_boot_anim,
        wipe_data=args.wipe_data,
    )
    if args.adb_visible_only:
        print("[boot] Start requests issued — waiting for ADB visibility")
    else:
        print("[boot] Start requests issued — waiting for Android boot completion")

    found = wait_for_emulators(
        manager,
        specs,
        args.timeout,
        args.interval,
        adb_visible_only=args.adb_visible_only,
    )
    if len(found) >= len(specs):
        if args.adb_visible_only:
            print(f"[boot] Success: found {len(found)} emulator(s): {found}")
        else:
            print(
                f"[boot] Success: boot completed for {len(found)} emulator(s): {found}"
            )
        return 0
    else:
        if args.adb_visible_only:
            print(f"[boot] Timeout: only found {len(found)} emulator(s): {found}")
        else:
            print(
                "[boot] Timeout: boot completed for "
                f"{len(found)} emulator(s): {found}"
            )
        return 1


if __name__ == "__main__":
    sys.exit(main())
