#!/usr/bin/env python3
"""Provision and verify Android devices are on the HydraCam Wi-Fi LAN.

The Wi-Fi password is intentionally never accepted as a command-line flag.
Set HYDRACAM_WIFI_PASSWORD or enter it at the prompt when provisioning is
needed.
"""

from __future__ import annotations

import argparse
import getpass
import ipaddress
import os
import re
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Sequence

DEFAULT_ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")


@dataclass(frozen=True)
class AndroidDevice:
    serial: str
    descriptor: str


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str

    @property
    def combined_output(self) -> str:
        return "\n".join(part for part in (self.stdout, self.stderr) if part)


@dataclass(frozen=True)
class DeviceNetworkState:
    serial: str
    model: str
    android_version: str
    wifi_on_value: str
    wifi_status: str
    route_output: str
    wlan0_ip: str | None
    on_expected_subnet: bool
    supports_connect_network: bool


def run_command(
    command: Sequence[str],
    *,
    timeout: int,
    secret: str | None = None,
    check: bool = False,
) -> CommandResult:
    completed = subprocess.run(
        command,
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    result = CommandResult(
        returncode=completed.returncode,
        stdout=redact(completed.stdout, secret),
        stderr=redact(completed.stderr, secret),
    )
    if check and result.returncode != 0:
        printable = " ".join(redact(part, secret) for part in command)
        raise RuntimeError(
            f"Command failed ({result.returncode}): {printable}\n"
            f"{result.combined_output}"
        )
    return result


def redact(value: str, secret: str | None) -> str:
    if not secret:
        return value
    return value.replace(secret, "<redacted>")


def adb_shell(
    adb: str,
    serial: str,
    shell_args: Sequence[str],
    *,
    timeout: int,
    secret: str | None = None,
) -> CommandResult:
    remote_command = " ".join(shlex.quote(arg) for arg in shell_args)
    return run_command(
        [adb, "-s", serial, "shell", remote_command],
        timeout=timeout,
        secret=secret,
    )


def list_devices(adb: str, timeout: int) -> list[AndroidDevice]:
    result = run_command([adb, "devices", "-l"], timeout=timeout, check=True)
    devices: list[AndroidDevice] = []
    for line in result.stdout.splitlines()[1:]:
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split(maxsplit=2)
        if len(parts) < 2 or parts[1] != "device":
            continue
        descriptor = parts[2] if len(parts) > 2 else ""
        devices.append(AndroidDevice(serial=parts[0], descriptor=descriptor))
    return devices


def read_prop(adb: str, serial: str, prop: str, timeout: int) -> str:
    result = adb_shell(adb, serial, ["getprop", prop], timeout=timeout)
    return result.stdout.strip() or "unknown"


def supports_connect_network(adb: str, serial: str, timeout: int) -> bool:
    result = adb_shell(adb, serial, ["cmd", "wifi", "help"], timeout=timeout)
    return "connect-network <ssid>" in result.combined_output


def extract_wlan0_ip(route_output: str) -> str | None:
    for line in route_output.splitlines():
        if " dev wlan0 " not in f" {line} ":
            continue
        match = re.search(r"\bsrc\s+([0-9]+(?:\.[0-9]+){3})\b", line)
        if match:
            return match.group(1)
    return None


def parse_route_interface(route_output: str) -> str | None:
    for line in route_output.splitlines():
        match = re.match(r"\s*interface:\s*(\S+)\s*$", line)
        if match:
            return match.group(1)
    return None


def parse_ifconfig_ipv4_network(
    ifconfig_output: str,
) -> ipaddress.IPv4Network | None:
    for line in ifconfig_output.splitlines():
        match = re.search(
            r"\binet\s+([0-9]+(?:\.[0-9]+){3})\s+netmask\s+(\S+)",
            line,
        )
        if not match:
            continue
        address = match.group(1)
        if address.startswith("127."):
            continue
        netmask = match.group(2)
        if netmask.startswith("0x"):
            netmask = str(ipaddress.IPv4Address(int(netmask, 16)))
        return ipaddress.ip_network(f"{address}/{netmask}", strict=False)
    return None


def infer_expected_subnet_from_host(
    expected_host: str,
    timeout: int,
) -> ipaddress.IPv4Network:
    route = run_command(
        ["route", "-n", "get", expected_host],
        timeout=timeout,
        check=True,
    )
    interface = parse_route_interface(route.combined_output)
    if not interface:
        raise RuntimeError(f"Could not resolve route interface for {expected_host}")

    ifconfig = run_command(["ifconfig", interface], timeout=timeout, check=True)
    network = parse_ifconfig_ipv4_network(ifconfig.stdout)
    if not network:
        raise RuntimeError(f"Could not resolve IPv4 subnet for interface {interface}")
    return network


def resolve_expected_subnet(
    expected_subnet: str,
    expected_host: str,
    timeout: int,
) -> ipaddress.IPv4Network:
    if expected_subnet.lower() != "auto":
        return ipaddress.ip_network(expected_subnet, strict=False)
    return infer_expected_subnet_from_host(expected_host, timeout)


def inspect_device(
    adb: str,
    device: AndroidDevice,
    expected_subnet: ipaddress.IPv4Network,
    timeout: int,
) -> DeviceNetworkState:
    wifi_status = adb_shell(
        adb,
        device.serial,
        ["cmd", "wifi", "status"],
        timeout=timeout,
    ).combined_output.strip()
    wifi_on_value = adb_shell(
        adb,
        device.serial,
        ["settings", "get", "global", "wifi_on"],
        timeout=timeout,
    ).stdout.strip()
    route_output = adb_shell(
        adb,
        device.serial,
        ["ip", "route"],
        timeout=timeout,
    ).stdout.strip()
    wlan0_ip = extract_wlan0_ip(route_output)
    on_expected_subnet = bool(
        wlan0_ip and ipaddress.ip_address(wlan0_ip) in expected_subnet
    )
    return DeviceNetworkState(
        serial=device.serial,
        model=read_prop(adb, device.serial, "ro.product.model", timeout),
        android_version=read_prop(
            adb,
            device.serial,
            "ro.build.version.release",
            timeout,
        ),
        wifi_on_value=wifi_on_value,
        wifi_status=wifi_status,
        route_output=route_output,
        wlan0_ip=wlan0_ip,
        on_expected_subnet=on_expected_subnet,
        supports_connect_network=supports_connect_network(
            adb,
            device.serial,
            timeout,
        ),
    )


def print_state(state: DeviceNetworkState) -> None:
    status = "OK" if state.on_expected_subnet else "NEEDS WIFI"
    print(
        f"[{status}] {state.serial} {state.model} Android {state.android_version} "
        f"wlan0={state.wlan0_ip or 'none'} wifi_on={state.wifi_on_value}"
    )
    if state.wifi_status:
        first_line = state.wifi_status.splitlines()[0]
        print(f"  wifi: {first_line}")
    if state.route_output:
        print("  routes:")
        for line in state.route_output.splitlines():
            if "wlan0" in line:
                print(f"    {line}")


def get_password() -> str:
    password = os.environ.get("HYDRACAM_WIFI_PASSWORD")
    if password:
        return password
    return getpass.getpass("Wi-Fi password: ")


def provision_device(
    adb: str,
    serial: str,
    ssid: str,
    security: str,
    password: str,
    timeout: int,
) -> None:
    print(f"  enabling Wi-Fi on {serial}")
    adb_shell(
        adb,
        serial,
        ["cmd", "wifi", "set-wifi-enabled", "enabled"],
        timeout=timeout,
        secret=password,
    )
    print(f"  connecting {serial} to {ssid} with {security} <redacted>")
    result = adb_shell(
        adb,
        serial,
        ["cmd", "wifi", "connect-network", ssid, security, password],
        timeout=timeout,
        secret=password,
    )
    if result.combined_output.strip():
        print("  " + result.combined_output.strip().replace("\n", "\n  "))


def open_wifi_settings(adb: str, serial: str, timeout: int) -> None:
    print(f"  opening Wi-Fi settings on {serial}; finish setup on the device")
    adb_shell(
        adb,
        serial,
        ["am", "start", "-a", "android.settings.WIFI_SETTINGS"],
        timeout=timeout,
    )


def wait_for_expected_subnet(
    adb: str,
    device: AndroidDevice,
    expected_subnet: ipaddress.IPv4Network,
    timeout: int,
    wait_seconds: int,
) -> DeviceNetworkState:
    deadline = time.time() + wait_seconds
    state = inspect_device(adb, device, expected_subnet, timeout)
    while not state.on_expected_subnet and time.time() < deadline:
        time.sleep(2)
        state = inspect_device(adb, device, expected_subnet, timeout)
    return state


def select_devices(
    devices: list[AndroidDevice],
    requested_serials: Sequence[str],
) -> list[AndroidDevice]:
    if not requested_serials:
        return devices
    requested = set(requested_serials)
    selected = [device for device in devices if device.serial in requested]
    missing = requested - {device.serial for device in selected}
    if missing:
        raise SystemExit(f"Requested devices not found: {', '.join(sorted(missing))}")
    return selected


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify and optionally provision Android Wi-Fi for HydraCam.",
    )
    parser.add_argument(
        "--adb",
        default=os.environ.get("ADB", DEFAULT_ADB),
        help="Path to adb. Defaults to Android SDK platform-tools.",
    )
    parser.add_argument(
        "--ssid",
        default=os.environ.get("HYDRACAM_WIFI_SSID"),
        help="Target SSID. May also be set with HYDRACAM_WIFI_SSID.",
    )
    parser.add_argument(
        "--security",
        default="wpa2",
        choices=("open", "owe", "wpa2", "wpa3"),
        help="Target network security type for Android cmd wifi.",
    )
    parser.add_argument(
        "--expected-subnet",
        default=os.environ.get("HYDRACAM_EXPECTED_SUBNET", "auto"),
        help=(
            "Expected HydraCam LAN subnet, for example 192.168.178.0/24. "
            "Use auto to infer it from the Mac route to --expected-host."
        ),
    )
    parser.add_argument(
        "--expected-host",
        default=os.environ.get("HYDRACAM_EXPECTED_HOST", "1.1.1.1"),
        help=(
            "Host used when --expected-subnet=auto. Use a known device bridge "
            "IP, such as a reachable iPhone automation host, when available."
        ),
    )
    parser.add_argument(
        "--device",
        action="append",
        default=[],
        help="ADB serial to include. Repeat to select multiple devices.",
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Inspect devices without attempting to connect or opening settings.",
    )
    parser.add_argument(
        "--wait-seconds",
        type=int,
        default=30,
        help="Seconds to wait for a provisioned device to receive a wlan0 route.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        help="Per-adb-command timeout in seconds.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    try:
        expected_subnet = resolve_expected_subnet(
            args.expected_subnet,
            args.expected_host,
            args.timeout,
        )
    except (RuntimeError, ValueError) as exc:
        raise SystemExit(f"Could not resolve expected subnet: {exc}") from exc

    adb = os.path.expanduser(args.adb)
    if not os.path.exists(adb):
        raise SystemExit(f"adb not found at {adb}")

    devices = select_devices(list_devices(adb, args.timeout), args.device)
    if not devices:
        raise SystemExit("No Android devices are attached or authorized.")

    if args.expected_subnet.lower() == "auto":
        print(f"Expected subnet: {expected_subnet} (inferred from {args.expected_host})")
    else:
        print(f"Expected subnet: {expected_subnet}")
    password: str | None = None
    final_states: list[DeviceNetworkState] = []

    for device in devices:
        state = inspect_device(adb, device, expected_subnet, args.timeout)
        print_state(state)
        if state.on_expected_subnet or args.check_only:
            final_states.append(state)
            continue

        if not args.ssid:
            print("  missing --ssid or HYDRACAM_WIFI_SSID; cannot provision")
            final_states.append(state)
            continue

        if state.supports_connect_network:
            password = password if password is not None else get_password()
            provision_device(
                adb,
                device.serial,
                args.ssid,
                args.security,
                password,
                args.timeout,
            )
            state = wait_for_expected_subnet(
                adb,
                device,
                expected_subnet,
                args.timeout,
                args.wait_seconds,
            )
            print_state(state)
            final_states.append(state)
            continue

        open_wifi_settings(adb, device.serial, args.timeout)
        final_states.append(state)

    failed = [state for state in final_states if not state.on_expected_subnet]
    if failed:
        print("\nDevices not ready for HydraCam LAN:")
        for state in failed:
            print(f"  {state.serial} {state.model} wlan0={state.wlan0_ip or 'none'}")
        return 2

    print("\nAll selected Android devices have wlan0 on the expected subnet.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
