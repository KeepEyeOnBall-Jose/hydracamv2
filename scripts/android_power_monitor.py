#!/usr/bin/env python3
"""Sample Android battery and HydraCam process CPU over ADB."""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Sequence

from hydracam_lib.adb import (
    DEFAULT_ADB,
    AndroidDevice,
    adb_shell_command,
    list_devices,
    select_devices,
)
from hydracam_lib.proc import CommandResult
from hydracam_lib.proc import run as run_command

DEFAULT_PACKAGE = "com.amaia23.hydracam"
DEFAULT_FIELDS = (
    "capacity",
    "status",
    "health",
    "present",
    "online",
    "current_now",
    "current_avg",
    "batt_current_ua_now",
    "batt_current_ua_avg",
    "voltage_now",
    "voltage_avg",
    "batt_voltage_now",
    "power_now",
    "power_avg",
    "temp",
    "temperature",
    "batt_temp",
    "usb_temp",
    "charge_type",
    "charging_type",
    "batt_charging_source",
    "batt_high_current_usb",
    "lcd",
    "camera",
    "video",
)


@dataclass
class CpuSnapshot:
    total_ticks: int
    cpu_count: int
    process_ticks: int | None


def shell_text(
    adb: str,
    serial: str,
    shell_args: Sequence[str],
    *,
    timeout: int,
    runner: Callable[..., CommandResult] = run_command,
) -> str | None:
    result = runner(adb_shell_command(adb, serial, shell_args), timeout=timeout)
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def parse_scalar(value: str) -> bool | int | float | str:
    lowered = value.strip().lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    try:
        return int(value)
    except ValueError:
        try:
            return float(value)
        except ValueError:
            return value.strip()


def normalize_key(key: str) -> str:
    return (
        key.strip()
        .lower()
        .replace(" ", "_")
        .replace("-", "_")
        .replace("/", "_")
        .replace(":", "")
    )


def parse_dumpsys_battery(output: str) -> dict[str, bool | int | float | str]:
    values: dict[str, bool | int | float | str] = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        normalized = normalize_key(key)
        if not normalized:
            continue
        values[normalized] = parse_scalar(value.strip())
    return values


def parse_proc_stat(output: str) -> tuple[int, int]:
    total_ticks = 0
    cpu_count = 0
    for line in output.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "cpu":
            total_ticks = sum(int(value) for value in parts[1:] if value.isdigit())
        elif parts[0].startswith("cpu") and parts[0][3:].isdigit():
            cpu_count += 1
    return total_ticks, cpu_count


def parse_proc_pid_stat(output: str) -> int | None:
    close_paren = output.rfind(")")
    if close_paren == -1:
        return None
    fields = output[close_paren + 2 :].split()
    if len(fields) < 15:
        return None
    try:
        utime = int(fields[11])
        stime = int(fields[12])
    except ValueError:
        return None
    return utime + stime


def cpu_percentages(
    previous: CpuSnapshot | None,
    current: CpuSnapshot,
) -> dict[str, float] | None:
    if (
        previous is None
        or previous.process_ticks is None
        or current.process_ticks is None
        or current.total_ticks <= previous.total_ticks
    ):
        return None
    process_delta = current.process_ticks - previous.process_ticks
    total_delta = current.total_ticks - previous.total_ticks
    if process_delta < 0 or total_delta <= 0:
        return None
    total_pct = (process_delta / total_delta) * 100
    return {
        "app_cpu_total_pct": total_pct,
        "app_cpu_core_pct": total_pct * max(current.cpu_count, 1),
    }


def read_pid_list(
    adb: str,
    serial: str,
    package: str,
    *,
    timeout: int,
    runner: Callable[..., CommandResult],
) -> list[int]:
    output = shell_text(
        adb,
        serial,
        ["pidof", package],
        timeout=timeout,
        runner=runner,
    )
    if not output:
        return []
    pids: list[int] = []
    for token in output.split():
        try:
            pids.append(int(token))
        except ValueError:
            continue
    return pids


def read_cpu_snapshot(
    adb: str,
    serial: str,
    pids: Sequence[int],
    *,
    timeout: int,
    runner: Callable[..., CommandResult],
) -> CpuSnapshot:
    stat_output = shell_text(
        adb,
        serial,
        ["cat", "/proc/stat"],
        timeout=timeout,
        runner=runner,
    )
    total_ticks, cpu_count = parse_proc_stat(stat_output or "")
    process_ticks = 0
    readable_pid_count = 0
    for pid in pids:
        pid_stat = shell_text(
            adb,
            serial,
            ["cat", f"/proc/{pid}/stat"],
            timeout=timeout,
            runner=runner,
        )
        ticks = parse_proc_pid_stat(pid_stat or "")
        if ticks is not None:
            process_ticks += ticks
            readable_pid_count += 1
    return CpuSnapshot(
        total_ticks=total_ticks,
        cpu_count=cpu_count,
        process_ticks=process_ticks if readable_pid_count else None,
    )


def read_sysfs_fields(
    adb: str,
    serial: str,
    fields: Sequence[str],
    *,
    timeout: int,
    runner: Callable[..., CommandResult],
) -> dict[str, Any]:
    values: dict[str, Any] = {}
    for field in fields:
        value = shell_text(
            adb,
            serial,
            ["cat", f"/sys/class/power_supply/battery/{field}"],
            timeout=timeout,
            runner=runner,
        )
        if value is None or value == "":
            continue
        values[field] = parse_scalar(value)
    return values


def read_brightness(
    adb: str,
    serial: str,
    *,
    timeout: int,
    runner: Callable[..., CommandResult],
) -> dict[str, Any]:
    brightness = shell_text(
        adb,
        serial,
        ["settings", "get", "system", "screen_brightness"],
        timeout=timeout,
        runner=runner,
    )
    mode = shell_text(
        adb,
        serial,
        ["settings", "get", "system", "screen_brightness_mode"],
        timeout=timeout,
        runner=runner,
    )
    return {
        "screen_brightness": parse_scalar(brightness) if brightness else None,
        "screen_brightness_mode": parse_scalar(mode) if mode else None,
    }


def read_device_identity(
    adb: str,
    serial: str,
    *,
    timeout: int,
    runner: Callable[..., CommandResult],
) -> dict[str, Any]:
    return {
        "model": shell_text(
            adb,
            serial,
            ["getprop", "ro.product.model"],
            timeout=timeout,
            runner=runner,
        ),
        "android_release": shell_text(
            adb,
            serial,
            ["getprop", "ro.build.version.release"],
            timeout=timeout,
            runner=runner,
        ),
        "android_sdk": shell_text(
            adb,
            serial,
            ["getprop", "ro.build.version.sdk"],
            timeout=timeout,
            runner=runner,
        ),
    }


def sample_device(
    adb: str,
    device: AndroidDevice,
    *,
    package: str,
    process_names: Sequence[str],
    timeout: int,
    fields: Sequence[str],
    previous_cpu: dict[str, CpuSnapshot],
    runner: Callable[..., CommandResult],
) -> tuple[dict[str, Any], dict[str, CpuSnapshot]]:
    pids = read_pid_list(
        adb,
        device.serial,
        package,
        timeout=timeout,
        runner=runner,
    )
    cpu_snapshot = read_cpu_snapshot(
        adb,
        device.serial,
        pids,
        timeout=timeout,
        runner=runner,
    )
    process_snapshots = {"app": cpu_snapshot}
    monitored_processes: dict[str, Any] = {}
    for process_name in process_names:
        process_pids = read_pid_list(
            adb,
            device.serial,
            process_name,
            timeout=timeout,
            runner=runner,
        )
        process_snapshot = read_cpu_snapshot(
            adb,
            device.serial,
            process_pids,
            timeout=timeout,
            runner=runner,
        )
        process_snapshots[process_name] = process_snapshot
        process_sample: dict[str, Any] = {
            "pids": process_pids,
            "cpu_total_ticks": process_snapshot.total_ticks,
            "cpu_count": process_snapshot.cpu_count,
            "process_ticks": process_snapshot.process_ticks,
        }
        process_cpu = cpu_percentages(
            previous_cpu.get(process_name),
            process_snapshot,
        )
        if process_cpu:
            process_sample["cpu_total_pct"] = process_cpu["app_cpu_total_pct"]
            process_sample["cpu_core_pct"] = process_cpu["app_cpu_core_pct"]
        monitored_processes[process_name] = process_sample

    battery_output = shell_text(
        adb,
        device.serial,
        ["dumpsys", "battery"],
        timeout=timeout,
        runner=runner,
    )
    sample: dict[str, Any] = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "serial": device.serial,
        "descriptor": device.descriptor,
        "package": package,
        "pids": pids,
        "cpu_total_ticks": cpu_snapshot.total_ticks,
        "cpu_count": cpu_snapshot.cpu_count,
        "app_process_ticks": cpu_snapshot.process_ticks,
        "monitored_processes": monitored_processes,
        "battery": parse_dumpsys_battery(battery_output or ""),
        "sysfs": read_sysfs_fields(
            adb,
            device.serial,
            fields,
            timeout=timeout,
            runner=runner,
        ),
        "brightness": read_brightness(
            adb,
            device.serial,
            timeout=timeout,
            runner=runner,
        ),
    }
    cpu_values = cpu_percentages(previous_cpu.get("app"), cpu_snapshot)
    if cpu_values:
        sample.update(cpu_values)
    return sample, process_snapshots


def summarize(samples: Sequence[dict[str, Any]]) -> dict[str, Any]:
    by_serial: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for sample in samples:
        by_serial[str(sample["serial"])].append(sample)

    summary: dict[str, Any] = {
        "sampleCount": len(samples),
        "devices": {},
    }
    for serial, device_samples in by_serial.items():
        cpu_values = [
            float(sample["app_cpu_core_pct"])
            for sample in device_samples
            if sample.get("app_cpu_core_pct") is not None
        ]
        current_raw_values = [
            int(sample["battery"]["current_now"])
            for sample in device_samples
            if isinstance(sample.get("battery"), dict)
            and isinstance(sample["battery"].get("current_now"), int)
        ]
        level_values = [
            int(sample["battery"]["level"])
            for sample in device_samples
            if isinstance(sample.get("battery"), dict)
            and isinstance(sample["battery"].get("level"), int)
        ]
        temp_values = [
            int(sample["battery"]["temperature"])
            for sample in device_samples
            if isinstance(sample.get("battery"), dict)
            and isinstance(sample["battery"].get("temperature"), int)
        ]
        latest = device_samples[-1]
        monitored_summary: dict[str, Any] = {}
        monitored_names = sorted(
            {
                process_name
                for sample in device_samples
                for process_name in sample.get("monitored_processes", {})
            }
        )
        for process_name in monitored_names:
            process_values = [
                float(
                    sample["monitored_processes"][process_name][
                        "cpu_core_pct"
                    ]
                )
                for sample in device_samples
                if sample.get("monitored_processes", {})
                .get(process_name, {})
                .get("cpu_core_pct")
                is not None
            ]
            latest_process = latest.get("monitored_processes", {}).get(
                process_name,
                {},
            )
            process_summary: dict[str, Any] = {
                "latestPids": latest_process.get("pids", []),
                "latestProcessTicks": latest_process.get("process_ticks"),
            }
            if process_values:
                process_summary["cpuCorePctMean"] = statistics.fmean(
                    process_values
                )
                process_summary["cpuCorePctMax"] = max(process_values)
            monitored_summary[process_name] = process_summary

        device_summary: dict[str, Any] = {
            "samples": len(device_samples),
            "latestBattery": latest.get("battery", {}),
            "latestBrightness": latest.get("brightness", {}),
            "latestPids": latest.get("pids", []),
            "monitoredProcesses": monitored_summary,
        }
        if cpu_values:
            device_summary["appCpuCorePctMean"] = statistics.fmean(cpu_values)
            device_summary["appCpuCorePctMax"] = max(cpu_values)
        if current_raw_values:
            device_summary["currentNowRawMean"] = statistics.fmean(current_raw_values)
            device_summary["currentNowRawMin"] = min(current_raw_values)
            device_summary["currentNowRawMax"] = max(current_raw_values)
        if level_values:
            device_summary["levelMin"] = min(level_values)
            device_summary["levelMax"] = max(level_values)
        if temp_values:
            device_summary["temperatureTenthsCMean"] = statistics.fmean(temp_values)
            device_summary["temperatureTenthsCMax"] = max(temp_values)
        summary["devices"][serial] = device_summary
    return summary


def print_sample(sample: dict[str, Any]) -> None:
    battery = sample.get("battery", {})
    brightness = sample.get("brightness", {})
    cpu = sample.get("app_cpu_core_pct")
    cpu_text = "n/a" if cpu is None else f"{cpu:.2f}%"
    monitored_parts = []
    for process_name, process_sample in sample.get(
        "monitored_processes",
        {},
    ).items():
        process_cpu = process_sample.get("cpu_core_pct")
        process_cpu_text = "n/a" if process_cpu is None else f"{process_cpu:.2f}%"
        monitored_parts.append(f"{process_name}_cpu_core={process_cpu_text}")
    print(
        " ".join(
            [
                str(sample["serial"]),
                f"level={battery.get('level', 'n/a')}",
                f"usb={battery.get('usb_powered', 'n/a')}",
                f"status={battery.get('status', 'n/a')}",
                f"voltage={battery.get('voltage', 'n/a')}",
                f"temp={battery.get('temperature', 'n/a')}",
                f"current_now_raw={battery.get('current_now', 'n/a')}",
                f"brightness={brightness.get('screen_brightness', 'n/a')}",
                f"pids={sample.get('pids', [])}",
                f"app_cpu_core={cpu_text}",
                *monitored_parts,
            ]
        )
    )


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
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
        "--package",
        default=DEFAULT_PACKAGE,
        help=f"Android package to monitor. Defaults to {DEFAULT_PACKAGE}.",
    )
    parser.add_argument(
        "--process-name",
        action="append",
        default=["cameraserver"],
        help=(
            "Additional process name to monitor with pidof. Repeat to include "
            "more. Defaults to cameraserver."
        ),
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=60,
        help="Total sampling duration in seconds.",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=10,
        help="Seconds between sample starts.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=10,
        help="Per-adb-command timeout in seconds.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional JSONL output path for raw samples.",
    )
    parser.add_argument(
        "--summary-output",
        type=Path,
        help="Optional JSON output path for the aggregate summary.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    devices = select_devices(
        list_devices(args.adb, timeout=args.timeout),
        args.device,
    )
    if not devices:
        raise SystemExit("No attached Android devices found.")

    identities = {
        device.serial: read_device_identity(
            args.adb,
            device.serial,
            timeout=args.timeout,
            runner=run_command,
        )
        for device in devices
    }

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.summary_output:
        args.summary_output.parent.mkdir(parents=True, exist_ok=True)

    start = time.monotonic()
    next_sample = start
    previous_cpu: dict[str, dict[str, CpuSnapshot]] = {}
    samples: list[dict[str, Any]] = []

    while True:
        now = time.monotonic()
        if now < next_sample:
            time.sleep(next_sample - now)
        elapsed = time.monotonic() - start
        for device in devices:
            sample, cpu_snapshot = sample_device(
                args.adb,
                device,
                package=args.package,
                process_names=args.process_name,
                timeout=args.timeout,
                fields=DEFAULT_FIELDS,
                previous_cpu=previous_cpu.get(device.serial, {}),
                runner=run_command,
            )
            sample["elapsed_seconds"] = round(elapsed, 3)
            sample["identity"] = identities.get(device.serial, {})
            previous_cpu[device.serial] = cpu_snapshot
            samples.append(sample)
            print_sample(sample)
            if args.output:
                with args.output.open("a", encoding="utf-8") as handle:
                    handle.write(json.dumps(sample, sort_keys=True) + "\n")
        if elapsed >= args.duration:
            break
        next_sample += args.interval

    summary = summarize(samples)
    print(json.dumps(summary, indent=2, sort_keys=True))
    if args.summary_output:
        args.summary_output.write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
