#!/usr/bin/env python3
"""Enable and verify ADB-over-WiFi for USB-authorized Android devices."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Sequence


IPV4_PATTERN = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")


@dataclass(frozen=True)
class AndroidDevice:
    serial: str
    model: str
    android_version: str
    sdk: str
    ip_address: str

    @property
    def wireless_serial(self) -> str:
        return f"{self.ip_address}:{PORT}"


PORT = 5555


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


def adb(*args: str, timeout: int = 30, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run_command(["adb", *args], timeout=timeout, check=check)


def adb_shell(
    serial: str,
    command: str,
    *,
    timeout: int = 30,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return adb("-s", serial, "shell", command, timeout=timeout, check=check)


def list_usb_devices() -> list[str]:
    result = adb("devices", "-l")
    serials: list[str] = []
    for line in result.stdout.splitlines()[1:]:
        columns = line.split()
        if len(columns) < 2 or columns[1] != "device":
            continue
        serial = columns[0]
        if ":" in serial:
            continue
        serials.append(serial)
    return serials


def get_prop(serial: str, prop: str) -> str:
    result = adb_shell(serial, f"getprop {prop}")
    return result.stdout.strip() or "unknown"


def get_wlan_ip(serial: str) -> str:
    probes = (
        "ip -o -4 addr show wlan0",
        "ip -f inet addr show wlan0",
        "ifconfig wlan0",
    )
    outputs: list[str] = []
    for probe in probes:
        result = adb_shell(serial, probe, check=False)
        combined = "\n".join(
            part for part in (result.stdout.strip(), result.stderr.strip()) if part
        )
        if combined:
            outputs.append(f"$ {probe}\n{combined}")
        for ip_address in IPV4_PATTERN.findall(combined):
            if ip_address != "127.0.0.1" and not ip_address.startswith("169.254."):
                return ip_address
    details = "\n\n".join(outputs) if outputs else "<no wlan0 output>"
    raise RuntimeError(f"Could not find a wlan0 IPv4 address for {serial}.\n{details}")


def inspect_device(serial: str) -> AndroidDevice:
    return AndroidDevice(
        serial=serial,
        model=get_prop(serial, "ro.product.model"),
        android_version=get_prop(serial, "ro.build.version.release"),
        sdk=get_prop(serial, "ro.build.version.sdk"),
        ip_address=get_wlan_ip(serial),
    )


def enable_wireless(device: AndroidDevice, *, dry_run: bool) -> None:
    print(
        f"[android-wireless] {device.model} {device.serial}: "
        f"Android {device.android_version} API {device.sdk}, wlan0 {device.ip_address}"
    )
    if dry_run:
        print(f"[dry-run] adb -s {device.serial} tcpip {PORT}")
        print(f"[dry-run] adb connect {device.wireless_serial}")
        return

    tcpip = adb("-s", device.serial, "tcpip", str(PORT), timeout=15)
    print(tcpip.stdout.strip())
    time.sleep(2)

    connect = adb("connect", device.wireless_serial, timeout=15, check=False)
    combined = "\n".join(
        part for part in (connect.stdout.strip(), connect.stderr.strip()) if part
    )
    print(combined or f"adb connect {device.wireless_serial} produced no output")
    if connect.returncode != 0 or "unable" in combined.lower() or "failed" in combined.lower():
        raise RuntimeError(f"ADB could not connect to {device.wireless_serial}")

    state = adb("-s", device.wireless_serial, "get-state", timeout=15)
    if state.stdout.strip() != "device":
        raise RuntimeError(f"{device.wireless_serial} is not ready: {state.stdout.strip()}")
    print(f"[android-wireless] ready: flutter run -d {device.wireless_serial}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Switch USB-authorized Android phones to ADB-over-WiFi and verify "
            "the resulting <ip>:5555 targets."
        )
    )
    parser.add_argument(
        "--serial",
        action="append",
        dest="serials",
        help="USB serial to prepare. Repeat for multiple devices. Defaults to all USB ADB devices.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the commands without changing ADB transport mode.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if shutil.which("adb") is None:
        print("adb was not found on PATH", file=sys.stderr)
        return 2

    serials = args.serials or list_usb_devices()
    if not serials:
        print(
            "No USB-authorized Android devices found. Connect one phone by USB, "
            "enable USB debugging, and accept the RSA prompt."
        )
        return 1

    prepared: list[AndroidDevice] = []
    for serial in serials:
        device = inspect_device(serial)
        enable_wireless(device, dry_run=args.dry_run)
        prepared.append(device)

    print("\nPrepared Android wireless targets:")
    for device in prepared:
        print(
            f"- {device.model}: {device.wireless_serial} "
            f"(USB serial {device.serial}, Android {device.android_version})"
        )
    print("\nAfter unplugging USB, verify with: adb devices -l && flutter devices")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
