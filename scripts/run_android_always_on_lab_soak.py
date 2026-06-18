#!/usr/bin/env python3
"""Run an Android lab-managed always-on soak and write evidence files."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, NamedTuple, Sequence

DEFAULT_ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
DEFAULT_PACKAGE = "com.amaia23.hydracam"
DEFAULT_EXPECTED_MODEL = "SM-G970F"
DEFAULT_INTERVAL_SECONDS = 60.0
DEFAULT_DURATION_HOURS = 24.0
DEFAULT_TIMEOUT_SECONDS = 10
MAX_TEMPERATURE_TENTHS_C = 450
LOW_BATTERY_PERCENT = 25
CRITICAL_BATTERY_PERCENT = 10


class CommandResult(NamedTuple):
    returncode: int
    stdout: str
    stderr: str


class AndroidDevice(NamedTuple):
    serial: str
    descriptor: str


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def default_run_dir(now: datetime | None = None) -> Path:
    timestamp = (now or utc_now()).strftime("%Y%m%d-%H%M")
    return Path("logs/verification-runs") / f"{timestamp}-android-always-on-lab-soak"


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
    runner: Callable[..., CommandResult] = run_command,
) -> CommandResult:
    result = runner(command, timeout=timeout)
    if result.returncode != 0:
        printable = " ".join(command)
        output = "\n".join(part for part in (result.stdout, result.stderr) if part)
        raise RuntimeError(f"Command failed ({result.returncode}): {printable}\n{output}")
    return result


def adb_shell_command(adb: str, serial: str, shell_args: Sequence[str]) -> list[str]:
    return [adb, "-s", serial, "shell", *shell_args]


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
        devices.append(
            AndroidDevice(
                serial=parts[0],
                descriptor=parts[2] if len(parts) > 2 else "",
            )
        )
    return devices


def select_devices(
    devices: Sequence[AndroidDevice],
    requested_serials: Sequence[str],
) -> list[AndroidDevice]:
    if not requested_serials:
        return list(devices)
    requested = set(requested_serials)
    selected = [device for device in devices if device.serial in requested]
    missing = requested - {device.serial for device in selected}
    if missing:
        raise SystemExit(f"Requested devices not found: {', '.join(sorted(missing))}")
    return selected


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
        if normalized:
            values[normalized] = parse_scalar(value.strip())
    return values


def read_pid_list(
    adb: str,
    serial: str,
    package: str,
    *,
    timeout: int,
    runner: Callable[..., CommandResult] = run_command,
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


def read_device_identity(
    adb: str,
    serial: str,
    *,
    timeout: int,
    runner: Callable[..., CommandResult] = run_command,
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
    timeout: int,
    runner: Callable[..., CommandResult] = run_command,
) -> dict[str, Any]:
    battery_output = shell_text(
        adb,
        device.serial,
        ["dumpsys", "battery"],
        timeout=timeout,
        runner=runner,
    )
    return {
        "timestamp_utc": utc_now().isoformat(),
        "serial": device.serial,
        "descriptor": device.descriptor,
        "package": package,
        "pids": read_pid_list(
            adb,
            device.serial,
            package,
            timeout=timeout,
            runner=runner,
        ),
        "battery": parse_dumpsys_battery(battery_output or ""),
    }


def summarize_samples(samples: Sequence[dict[str, Any]]) -> dict[str, Any]:
    by_serial: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for sample in samples:
        by_serial[str(sample["serial"])].append(sample)

    summary: dict[str, Any] = {
        "sampleCount": len(samples),
        "devices": {},
    }
    for serial, device_samples in by_serial.items():
        latest = device_samples[-1]
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
        device_summary: dict[str, Any] = {
            "samples": len(device_samples),
            "latestBattery": latest.get("battery", {}),
            "latestPids": latest.get("pids", []),
        }
        if level_values:
            device_summary["levelMin"] = min(level_values)
            device_summary["levelMax"] = max(level_values)
        if temp_values:
            device_summary["temperatureTenthsCMax"] = max(temp_values)
        summary["devices"][serial] = device_summary
    return summary


def print_sample(sample: dict[str, Any]) -> None:
    battery = sample.get("battery", {})
    print(
        " ".join(
            [
                str(sample["serial"]),
                f"level={battery.get('level', 'n/a')}",
                f"usb={battery.get('usb_powered', 'n/a')}",
                f"ac={battery.get('ac_powered', 'n/a')}",
                f"status={battery.get('status', 'n/a')}",
                f"temp={battery.get('temperature', 'n/a')}",
                f"pids={sample.get('pids', [])}",
            ]
        )
    )


def is_powered(battery: dict[str, Any]) -> bool:
    return any(
        battery.get(key) is True
        for key in ("ac_powered", "usb_powered", "wireless_powered")
    )


def assess_soak(
    power_summary: dict[str, Any],
    identities: dict[str, dict[str, Any]],
    *,
    min_samples: int,
    expected_model: str | None,
    require_app_process: bool,
    bridge_checks: Sequence[dict[str, Any]],
    expected_bridge_target_ids: Sequence[str] = (),
) -> dict[str, Any]:
    failures: list[str] = []
    warnings: list[str] = []
    expected_bridge_targets = set(expected_bridge_target_ids)
    devices = power_summary.get("devices", {})
    if not isinstance(devices, dict) or not devices:
        failures.append("no-devices-sampled")
        devices = {}

    sample_count = power_summary.get("sampleCount", 0)
    if isinstance(sample_count, int) and sample_count < min_samples:
        failures.append("sample-count-below-minimum")

    for serial, device_summary in devices.items():
        if not isinstance(device_summary, dict):
            failures.append(f"{serial}:invalid-summary")
            continue

        samples = device_summary.get("samples", 0)
        if not isinstance(samples, int) or samples < min_samples:
            failures.append(f"{serial}:samples-below-minimum")

        identity = identities.get(serial, {})
        model = identity.get("model")
        if expected_model and model != expected_model:
            failures.append(f"{serial}:unexpected-model:{model}")

        latest_pids = device_summary.get("latestPids", [])
        if require_app_process and not latest_pids:
            failures.append(f"{serial}:app-process-missing")

        latest_battery = device_summary.get("latestBattery", {})
        if not isinstance(latest_battery, dict):
            latest_battery = {}

        if not is_powered(latest_battery):
            failures.append(f"{serial}:not-powered")

        battery_level = latest_battery.get("level")
        if isinstance(battery_level, int):
            if battery_level <= CRITICAL_BATTERY_PERCENT:
                failures.append(f"{serial}:battery-critical:{battery_level}")
            elif battery_level < LOW_BATTERY_PERCENT:
                warnings.append(f"{serial}:battery-low:{battery_level}")
        else:
            warnings.append(f"{serial}:battery-level-unknown")

        max_temperature = device_summary.get("temperatureTenthsCMax")
        if isinstance(max_temperature, (int, float)):
            if max_temperature >= MAX_TEMPERATURE_TENTHS_C:
                failures.append(f"{serial}:temperature-critical:{max_temperature}")
        else:
            warnings.append(f"{serial}:temperature-unknown")

    for index, check in enumerate(bridge_checks):
        if check.get("ok") is not True:
            failures.append(f"bridge-healthz-failed:{index}")
            continue
        if expected_bridge_targets:
            health_payload = check.get("json")
            automation_target_id = (
                health_payload.get("automationTargetId")
                if isinstance(health_payload, dict)
                else None
            )
            if not automation_target_id:
                failures.append(f"bridge-healthz-missing-identity:{index}")
            elif str(automation_target_id) not in expected_bridge_targets:
                failures.append(
                    "bridge-healthz-unexpected-target:"
                    f"{index}:{automation_target_id}"
                )

    return {
        "status": "failed" if failures else "passed",
        "deviceCount": len(devices),
        "minSamples": min_samples,
        "expectedModel": expected_model,
        "requireAppProcess": require_app_process,
        "failures": failures,
        "warnings": warnings,
    }


def probe_bridge_healthz(url: str, *, timeout: int) -> dict[str, Any]:
    started_at = utc_now().isoformat()
    try:
        request = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read(4096).decode("utf-8", errors="replace")
            parsed_body = None
            try:
                parsed_body = json.loads(body)
            except json.JSONDecodeError:
                parsed_body = None
            return {
                "url": url,
                "checkedAtUtc": started_at,
                "ok": 200 <= response.status < 300,
                "status": response.status,
                "body": body,
                "json": parsed_body,
            }
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        return {
            "url": url,
            "checkedAtUtc": started_at,
            "ok": False,
            "error": str(error),
        }


def write_evidence_files(
    run_dir: Path,
    *,
    metadata: dict[str, Any],
    samples: Sequence[dict[str, Any]],
    power_summary: dict[str, Any],
    assessment: dict[str, Any],
    bridge_checks: Sequence[dict[str, Any]],
) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    with (run_dir / "raw-samples.jsonl").open("w", encoding="utf-8") as handle:
        for sample in samples:
            handle.write(json.dumps(sample, sort_keys=True) + "\n")
    (run_dir / "power-summary.json").write_text(
        json.dumps(power_summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (run_dir / "bridge-healthz.json").write_text(
        json.dumps(list(bridge_checks), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    always_on_summary = {
        **assessment,
        "metadata": metadata,
        "powerSummaryPath": "power-summary.json",
        "rawSamplesPath": "raw-samples.jsonl",
        "bridgeHealthzPath": "bridge-healthz.json",
    }
    (run_dir / "always-on-summary.json").write_text(
        json.dumps(always_on_summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def collect_power_samples(
    *,
    adb: str,
    devices: Sequence[AndroidDevice],
    package: str,
    duration_seconds: float,
    interval_seconds: float,
    timeout: int,
    runner: Callable[..., CommandResult],
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    identities = {
        device.serial: read_device_identity(
            adb,
            device.serial,
            timeout=timeout,
            runner=runner,
        )
        for device in devices
    }

    start = time.monotonic()
    next_sample = start
    samples: list[dict[str, Any]] = []

    while True:
        now = time.monotonic()
        if now < next_sample:
            time.sleep(next_sample - now)
        elapsed = time.monotonic() - start

        for device in devices:
            sample = sample_device(
                adb,
                device,
                package=package,
                timeout=timeout,
                runner=runner,
            )
            sample["elapsed_seconds"] = round(elapsed, 3)
            sample["identity"] = identities.get(device.serial, {})
            samples.append(sample)
            print_sample(sample)

        if elapsed >= duration_seconds:
            break
        next_sample += interval_seconds

    return samples, identities


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
        help=f"HydraCam package to monitor. Defaults to {DEFAULT_PACKAGE}.",
    )
    parser.add_argument(
        "--duration-hours",
        type=float,
        default=DEFAULT_DURATION_HOURS,
        help="Total soak duration in hours. Defaults to 24.",
    )
    parser.add_argument(
        "--duration-seconds",
        type=float,
        help="Override duration for short smoke runs.",
    )
    parser.add_argument(
        "--interval-seconds",
        type=float,
        default=DEFAULT_INTERVAL_SECONDS,
        help="Seconds between sample starts. Defaults to 60.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT_SECONDS,
        help="Per-command timeout in seconds.",
    )
    parser.add_argument(
        "--expected-model",
        default=DEFAULT_EXPECTED_MODEL,
        help="Expected Android model. Use an empty value to skip model check.",
    )
    parser.add_argument(
        "--allow-missing-app-process",
        action="store_true",
        help="Do not fail if the HydraCam package has no running process.",
    )
    parser.add_argument(
        "--bridge-healthz-url",
        action="append",
        default=[],
        help="Optional HydraCam automation bridge /healthz URL to probe.",
    )
    parser.add_argument(
        "--run-dir",
        type=Path,
        default=None,
        help="Evidence output directory. Defaults under logs/verification-runs.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    duration_seconds = (
        args.duration_seconds
        if args.duration_seconds is not None
        else args.duration_hours * 60 * 60
    )
    if duration_seconds <= 0:
        raise SystemExit("--duration must be positive.")
    if args.interval_seconds <= 0:
        raise SystemExit("--interval-seconds must be positive.")

    run_dir = args.run_dir or default_run_dir()
    devices = select_devices(
        list_devices(args.adb, timeout=args.timeout),
        args.device,
    )
    if not devices:
        raise SystemExit("No attached Android devices found.")

    metadata = {
        "runId": run_dir.name,
        "startedAtUtc": utc_now().isoformat(),
        "adb": args.adb,
        "devices": [device.serial for device in devices],
        "package": args.package,
        "durationSeconds": duration_seconds,
        "intervalSeconds": args.interval_seconds,
        "expectedModel": args.expected_model or None,
        "mode": "lab-managed",
    }

    samples, identities = collect_power_samples(
        adb=args.adb,
        devices=devices,
        package=args.package,
        duration_seconds=duration_seconds,
        interval_seconds=args.interval_seconds,
        timeout=args.timeout,
        runner=run_command,
    )
    power_summary = summarize_samples(samples)
    bridge_checks = [
        probe_bridge_healthz(url, timeout=args.timeout)
        for url in args.bridge_healthz_url
    ]
    min_samples = max(1, int(duration_seconds // args.interval_seconds) + 1)
    assessment = assess_soak(
        power_summary,
        identities,
        min_samples=min_samples,
        expected_model=args.expected_model or None,
        require_app_process=not args.allow_missing_app_process,
        bridge_checks=bridge_checks,
        expected_bridge_target_ids=[device.serial for device in devices],
    )
    metadata["completedAtUtc"] = utc_now().isoformat()

    write_evidence_files(
        run_dir,
        metadata=metadata,
        samples=samples,
        power_summary=power_summary,
        assessment=assessment,
        bridge_checks=bridge_checks,
    )

    print(json.dumps({"runDir": str(run_dir), **assessment}, indent=2))
    return 0 if assessment["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
