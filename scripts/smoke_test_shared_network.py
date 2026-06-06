#!/usr/bin/env python3
"""Boot the Hydra emulator cluster, verify shared-net IPs, then shut it down."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from typing import Sequence

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from scripts.emulator_manager import EmulatorLaunchSpec, EmulatorManager, hydra_cluster_specs

IPV4_PATTERN = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")


def serial_for(spec: EmulatorLaunchSpec) -> str:
    return f"emulator-{spec.port}"


def expected_ip_for(spec: EmulatorLaunchSpec) -> str:
    if spec.shared_net_id is None:
        raise ValueError(f"{spec.avd_name} is missing shared_net_id")
    return f"10.1.2.{spec.shared_net_id}"


def run_command(
    command: Sequence[str],
    *,
    timeout: int = 30,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(command),
        check=check,
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def adb_shell(
    serial: str,
    command: str,
    *,
    timeout: int = 30,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return run_command(
        ["adb", "-s", serial, "shell", command],
        timeout=timeout,
        check=check,
    )


def wait_for_boot_completed(serial: str, timeout: int = 240) -> None:
    run_command(["adb", "-s", serial, "wait-for-device"], timeout=timeout)
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = adb_shell(serial, "getprop sys.boot_completed", check=False)
        if result.stdout.strip() == "1":
            return
        time.sleep(2)
    raise RuntimeError(f"{serial} did not finish booting within {timeout}s")


def get_ipv4_addresses(serial: str) -> tuple[list[str], str]:
    probe_commands = (
        "ip -o -4 addr show",
        "/system/bin/ip -o -4 addr show",
        "toybox ip -o -4 addr show",
        "ifconfig",
    )
    outputs: list[str] = []
    for probe in probe_commands:
        result = adb_shell(serial, probe, check=False)
        combined = "\n".join(
            part for part in (result.stdout.strip(), result.stderr.strip()) if part
        )
        if combined:
            outputs.append(f"$ {probe}\n{combined}")
        addresses = sorted(set(IPV4_PATTERN.findall(combined)))
        if addresses:
            return addresses, outputs[-1]

    joined = "\n\n".join(outputs) if outputs else "<no output>"
    raise RuntimeError(f"Could not read IPv4 addresses from {serial}.\n{joined}")


def collect_network_diagnostics(serial: str) -> str:
    commands = (
        "ip addr show",
        "ip link show",
        "ip route",
        "cat /proc/net/dev",
        "ifconfig",
    )
    sections: list[str] = []
    for command in commands:
        result = adb_shell(serial, command, check=False)
        combined = "\n".join(
            part for part in (result.stdout.strip(), result.stderr.strip()) if part
        )
        sections.append(f"$ {command}\n{combined or '<no output>'}")
    return "\n\n".join(sections)


def ping(serial: str, target_ip: str) -> str:
    probe_commands = (
        f"ping -c 1 {target_ip}",
        f"toybox ping -c 1 {target_ip}",
        f"/system/bin/ping -c 1 {target_ip}",
    )
    failures: list[str] = []
    for probe in probe_commands:
        try:
            result = adb_shell(serial, probe, timeout=15, check=False)
        except subprocess.TimeoutExpired:
            failures.append(f"$ {probe}\n<timed out>")
            continue

        combined = "\n".join(
            part for part in (result.stdout.strip(), result.stderr.strip()) if part
        )
        if result.returncode == 0:
            return f"$ {probe}\n{combined}".strip()
        failures.append(f"$ {probe}\n{combined}".strip())

    raise RuntimeError(
        f"{serial} could not reach {target_ip}.\n" + "\n\n".join(failures)
    )


def ensure_expected_ports_free(specs: Sequence[EmulatorLaunchSpec]) -> None:
    manager = EmulatorManager()
    running = set(manager.list_android_emulators())
    expected_serials = {serial_for(spec) for spec in specs}
    conflicts = sorted(running & expected_serials)
    if conflicts:
        raise RuntimeError(
            "These Hydra emulator serials are already running: "
            + ", ".join(conflicts)
            + ". Stop them first so the smoke test does not interfere."
        )


def stop_specs(manager: EmulatorManager, specs: Sequence[EmulatorLaunchSpec]) -> None:
    serials = [serial_for(spec) for spec in specs]
    for serial in serials:
        if serial in manager.list_android_emulators():
            manager.stop_android_emulator(serial)

    deadline = time.time() + 60
    remaining = sorted(set(manager.list_android_emulators()) & set(serials))
    while remaining and time.time() < deadline:
        time.sleep(2)
        remaining = sorted(set(manager.list_android_emulators()) & set(serials))

    if remaining:
        for spec in specs:
            if serial_for(spec) in remaining:
                subprocess.run(
                    ["pkill", "-f", f"-avd {spec.avd_name}"],
                    check=False,
                    capture_output=True,
                    text=True,
                )
        time.sleep(3)
        remaining = sorted(set(manager.list_android_emulators()) & set(serials))

    if remaining:
        raise RuntimeError(
            "Failed to stop emulator(s): " + ", ".join(remaining)
        )


def main() -> int:
    manager = EmulatorManager()
    specs = hydra_cluster_specs()
    ensure_expected_ports_free(specs)

    print("[smoke] Starting Hydra emulator cluster")
    for spec in specs:
        print(
            f"[smoke] {spec.avd_name}: {serial_for(spec)} -> {expected_ip_for(spec)}"
        )

    try:
        manager.start_emulator_specs(
            specs,
            wait_per_instance=True,
            per_instance_timeout=180,
            per_instance_interval=2.0,
        )

        print("[smoke] Waiting for Android boot completion")
        for spec in specs:
            wait_for_boot_completed(serial_for(spec))
            print(f"[smoke] {serial_for(spec)} booted")

        # Give the shared emulator network a moment to settle after boot.
        time.sleep(5)

        print("[smoke] Verifying shared-net IPs")
        for spec in specs:
            serial = serial_for(spec)
            expected_ip = expected_ip_for(spec)
            addresses, source_output = get_ipv4_addresses(serial)
            if expected_ip not in addresses:
                diagnostics = collect_network_diagnostics(serial)
                raise RuntimeError(
                    f"{serial} is missing expected IP {expected_ip}. "
                    f"Observed addresses: {addresses}\n{source_output}\n\n{diagnostics}"
                )
            print(f"[smoke] {serial} has {expected_ip}")

        print("[smoke] Verifying emulator-to-emulator connectivity")
        master = specs[0]
        slaves = specs[1:]
        checks = [(master, slave) for slave in slaves] + [
            (slave, master) for slave in slaves
        ]
        for source, target in checks:
            source_serial = serial_for(source)
            target_ip = expected_ip_for(target)
            ping_output = ping(source_serial, target_ip)
            print(f"[smoke] {source_serial} can reach {target_ip}")
            print(ping_output)

        print("[smoke] Success: shared-net IPs are present and emulators can talk")
        return 0
    finally:
        print("[smoke] Stopping Hydra emulator cluster")
        stop_specs(manager, specs)
        print("[smoke] Hydra emulator cluster stopped")


if __name__ == "__main__":
    sys.exit(main())
