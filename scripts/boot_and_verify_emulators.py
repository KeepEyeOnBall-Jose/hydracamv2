#!/usr/bin/env python3
"""Start N Android emulators and verify they appear in `adb devices`.

Dry-run by default; pass `--start` to actually launch emulators.
"""

import argparse
import sys
import time
from typing import List

from scripts.emulator_manager import EmulatorManager


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

    if not args.start:
        print(
            "[boot] Dry-run: would start %d emulator(s) using AVD base '%s'",
            (args.count, args.avd_base),
        )
        print("[boot] To actually start emulators, pass --start")
        return 0

    print(f"[boot] Starting {args.count} emulator(s) (avd base '{args.avd_base}')")
    manager.start_n_emulators(args.avd_base, args.count, args.start_port)
    print("[boot] Start requests issued — waiting for devices to appear in adb")

    found = wait_for_emulators(manager, args.count, args.timeout, args.interval)
    if len(found) >= args.count:
        print(f"[boot] Success: found {len(found)} emulator(s): {found}")
        return 0
    else:
        print(f"[boot] Timeout: only found {len(found)} emulator(s): {found}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
