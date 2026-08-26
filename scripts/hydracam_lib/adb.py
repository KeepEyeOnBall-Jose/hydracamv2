"""ADB invocation helpers shared by the Android probing scripts.

Covers the pieces every probing script duplicated: the default ``adb`` path,
the ``AndroidDevice`` record, building an ``adb -s <serial> shell ...`` argv,
listing authorized devices from ``adb devices -l``, and filtering that list
down to a requested set of serials.
"""

from __future__ import annotations

import os
from typing import Callable, NamedTuple, Sequence

from hydracam_lib.proc import CommandResult, checked_run, run

DEFAULT_ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")


class AndroidDevice(NamedTuple):
    serial: str
    descriptor: str


def adb_shell_command(adb: str, serial: str, shell_args: Sequence[str]) -> list[str]:
    return [adb, "-s", serial, "shell", *shell_args]


def list_devices(
    adb: str,
    *,
    timeout: int,
    runner: Callable[..., CommandResult] = run,
) -> list[AndroidDevice]:
    """Return the ``device``-state entries from ``adb devices -l``.

    Rows in any other state (offline, unauthorized) are skipped.
    """
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
    devices: Sequence[AndroidDevice],
    requested_serials: Sequence[str],
) -> list[AndroidDevice]:
    """Filter ``devices`` to ``requested_serials`` (all of them when empty)."""
    if not requested_serials:
        return list(devices)
    requested = set(requested_serials)
    selected = [device for device in devices if device.serial in requested]
    missing = requested - {device.serial for device in selected}
    if missing:
        raise SystemExit(f"Requested devices not found: {', '.join(sorted(missing))}")
    return selected
