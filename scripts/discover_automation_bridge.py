#!/usr/bin/env python3
"""Discover a HydraCam automation bridge without running capture commands."""

from __future__ import annotations

import argparse
import json
import time

from ios_capture_repro import DEFAULT_PORT, DEFAULT_SCAN_SUBNET, discover_bridge


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--scan-subnet", default=DEFAULT_SCAN_SUBNET)
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument(
        "--required-command",
        help="Only return bridges exposing this automation command.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    bridge_url = discover_bridge(
        args.port,
        args.scan_subnet,
        time.time() + args.timeout,
        required_command=args.required_command,
    )
    print(
        json.dumps(
            {
                "bridgeUrl": bridge_url,
                "port": args.port,
                "scanSubnet": args.scan_subnet,
                "requiredCommand": args.required_command,
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
