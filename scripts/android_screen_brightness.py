#!/usr/bin/env python3
"""Dim or brighten attached Android devices for HydraCam debugging."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from typing import Callable, NamedTuple, Sequence

DEFAULT_ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
DEFAULT_DIM_BRIGHTNESS = 0
DEFAULT_BRIGHT_BRIGHTNESS = 180


class AndroidDevice(NamedTuple):
    serial: str
    descriptor: str


class CommandResult(NamedTuple):
    returncode: int
    stdout: str
    stderr: str

    @property
    def combined_output(self) -> str:
        return "\n".join(part for part in (self.stdout, self.stderr) if part)


class BrightnessState(NamedTuple):
    serial: str
    brightness: str
    mode: str


def run_command(command: list[str], *, timeout: int) -> CommandResult:
    completed = subprocess.run(
        command,
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    return CommandResult(
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def checked_run(
    command: list[str],
    *,
    timeout: int,
    runner: Callable[..., CommandResult],
) -> CommandResult:
    result = runner(command, timeout=timeout)
    if result.returncode != 0:
        printable = " ".join(command)
        raise RuntimeError(
            f"Command failed ({result.returncode}): {printable}\n"
            f"{result.combined_output}"
        )
    return result


def adb_shell_command(adb: str, serial: str, shell_args: Sequence[str]) -> list[str]:
    return [adb, "-s", serial, "shell", *shell_args]


def list_devices(
    adb: str,
    *,
    timeout: int,
    runner: Callable[..., CommandResult] = run_command,
) -> list[AndroidDevice]:
    result = checked_run([adb, "devices", "-l"], timeout=timeout, runner=runner)
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


def brightness_commands(serial: str, brightness: int, adb: str = "adb") -> list[list[str]]:
    return [
        adb_shell_command(
            adb,
            serial,
            ["settings", "put", "system", "screen_brightness_mode", "0"],
        ),
        adb_shell_command(
            adb,
            serial,
            ["settings", "put", "system", "screen_brightness", str(brightness)],
        ),
    ]


def set_device_brightness(
    adb: str,
    devices: Sequence[AndroidDevice],
    brightness: int,
    *,
    timeout: int,
    runner: Callable[..., CommandResult] = run_command,
) -> None:
    for device in devices:
        for command in brightness_commands(device.serial, brightness, adb=adb):
            checked_run(command, timeout=timeout, runner=runner)
        print(f"{device.serial}: screen_brightness={brightness}")


def status_devices(
    adb: str,
    devices: Sequence[AndroidDevice],
    *,
    timeout: int,
    runner: Callable[..., CommandResult] = run_command,
) -> list[BrightnessState]:
    states: list[BrightnessState] = []
    for device in devices:
        brightness = checked_run(
            adb_shell_command(
                adb,
                device.serial,
                ["settings", "get", "system", "screen_brightness"],
            ),
            timeout=timeout,
            runner=runner,
        ).stdout.strip()
        mode = checked_run(
            adb_shell_command(
                adb,
                device.serial,
                ["settings", "get", "system", "screen_brightness_mode"],
            ),
            timeout=timeout,
            runner=runner,
        ).stdout.strip()
        states.append(
            BrightnessState(
                serial=device.serial,
                brightness=brightness or "unknown",
                mode=mode or "unknown",
            )
        )
    return states


def valid_brightness(value: str) -> int:
    try:
        brightness = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("brightness must be an integer") from exc
    if not 0 <= brightness <= 255:
        raise argparse.ArgumentTypeError("brightness must be between 0 and 255")
    return brightness


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        choices=("dim", "bright", "status"),
        help="dim sets a low brightness, bright restores test brightness.",
    )
    parser.add_argument(
        "--adb",
        default=os.environ.get("ADB", DEFAULT_ADB),
        help="Path to adb. Defaults to Android SDK platform-tools.",
    )
    parser.add_argument(
        "--device",
        action="append",
        default=[],
        help="ADB serial to include. Repeat to select multiple devices.",
    )
    parser.add_argument(
        "--value",
        type=valid_brightness,
        help=(
            f"Brightness value from 0-255. Defaults: dim={DEFAULT_DIM_BRIGHTNESS}, "
            f"bright={DEFAULT_BRIGHT_BRIGHTNESS}."
        ),
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        help="Per-adb-command timeout in seconds.",
    )
    return parser.parse_args(argv)


def action_brightness(args: argparse.Namespace) -> int:
    if args.value is not None:
        return args.value
    if args.action == "dim":
        return DEFAULT_DIM_BRIGHTNESS
    return DEFAULT_BRIGHT_BRIGHTNESS


def main(
    argv: Sequence[str],
    *,
    runner: Callable[..., CommandResult] = run_command,
) -> int:
    args = parse_args(argv)
    adb = os.path.expanduser(args.adb)

    devices = select_devices(
        list_devices(adb, timeout=args.timeout, runner=runner),
        args.device,
    )
    if not devices:
        raise SystemExit("No Android devices are attached or authorized.")

    if args.action in ("dim", "bright"):
        set_device_brightness(
            adb,
            devices,
            action_brightness(args),
            timeout=args.timeout,
            runner=runner,
        )
        return 0

    for state in status_devices(
        adb,
        devices,
        timeout=args.timeout,
        runner=runner,
    ):
        mode = "manual" if state.mode == "0" else f"mode={state.mode}"
        print(f"{state.serial}: screen_brightness={state.brightness} {mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
