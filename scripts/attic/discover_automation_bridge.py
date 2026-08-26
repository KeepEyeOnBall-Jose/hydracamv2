#!/usr/bin/env python3
"""Discover a HydraCam automation bridge without running capture commands."""

from __future__ import annotations

import argparse
import concurrent.futures
import ipaddress
import json
import time

from ios_capture_repro import (
    DEFAULT_PORT,
    DEFAULT_SCAN_SUBNET,
    ReproError,
    _port_is_open,
    discover_bridge,
    request_json,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--scan-subnet", default=DEFAULT_SCAN_SUBNET)
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument(
        "--required-command",
        help="Only return bridges exposing this automation command.",
    )
    parser.add_argument(
        "--target-id",
        action="append",
        default=[],
        help="Only return bridges whose /healthz automationTargetId matches. May repeat.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Return all matching bridges instead of the first matching bridge.",
    )
    return parser.parse_args()


def discover_all_bridges(args: argparse.Namespace) -> list[dict[str, object]]:
    network = ipaddress.ip_network(args.scan_subnet, strict=False)
    hosts = [str(host) for host in network.hosts()]
    target_ids = set(args.target_id)
    matches: dict[str, dict[str, object]] = {}
    deadline = time.time() + args.timeout

    def probe(host: str) -> dict[str, object] | None:
        if not _port_is_open(host, args.port):
            return None
        bridge_url = f"http://{host}:{args.port}"
        try:
            health = request_json(bridge_url, "GET", "/healthz", timeout=2)
        except ReproError:
            return None
        commands = health.get("commands", [])
        has_required_command = args.required_command is None or (
            isinstance(commands, list) and args.required_command in commands
        )
        target_id = str(health.get("automationTargetId", ""))
        has_target = not target_ids or target_id in target_ids
        if health.get("status") != "ok" or not has_required_command or not has_target:
            return None
        return {
            "bridgeUrl": bridge_url,
            "host": host,
            "health": health,
            "automationTargetId": target_id,
        }

    while time.time() < deadline:
        with concurrent.futures.ThreadPoolExecutor(max_workers=128) as executor:
            futures = {executor.submit(probe, host): host for host in hosts}
            for future in concurrent.futures.as_completed(futures):
                match = future.result()
                if match is None:
                    continue
                matches[str(match["bridgeUrl"])] = match
        if matches:
            break
        time.sleep(1)

    return [matches[key] for key in sorted(matches)]


def main() -> int:
    args = parse_args()
    if args.all or args.target_id:
        bridges = discover_all_bridges(args)
        print(
            json.dumps(
                {
                    "bridges": bridges,
                    "count": len(bridges),
                    "port": args.port,
                    "scanSubnet": args.scan_subnet,
                    "requiredCommand": args.required_command,
                    "targetIds": args.target_id,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0 if bridges else 1

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
