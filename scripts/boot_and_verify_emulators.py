#!/usr/bin/env python3
"""Start N Android emulators and verify they appear in `adb devices`.

Dry-run by default; pass `--start` to actually launch emulators.
"""

# Make the project root importable so this script can be run directly
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import argparse
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
        help="Seconds to wait for emulators to appear in adb",
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


def wait_for_emulators(
    manager: EmulatorManager, want: int, timeout: int, interval: float
) -> List[str]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        ids = manager.list_android_emulators()
        if len(ids) >= want:
            return ids
        time.sleep(interval)
    return manager.list_android_emulators()


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
    manager.start_emulator_specs(specs)
    print("[boot] Start requests issued — waiting for devices to appear in adb")

    found = wait_for_emulators(manager, len(specs), args.timeout, args.interval)
    if len(found) >= len(specs):
        print(f"[boot] Success: found {len(found)} emulator(s): {found}")
        return 0
    else:
        print(f"[boot] Timeout: only found {len(found)} emulator(s): {found}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
