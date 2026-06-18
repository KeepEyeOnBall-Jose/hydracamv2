#!/usr/bin/env python3
"""Run a rotating HydraCam master/slave capture matrix.

Each capture-capable device is launched once as master. Every other discovered
target is launched as a forced slave pointed at that master's Wi-Fi host, then
the capture scenario is sent only through the master automation bridge.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import datetime as dt
import ipaddress
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse
import zipfile
from pathlib import Path
from typing import Any, Callable, Mapping, MutableMapping, Sequence, TypeVar

from ios_capture_repro import (
    DEFAULT_PORT,
    ReproError,
    launch_flutter,
    post_command,
    request_json,
    stop_flutter,
    wait_for_bridge,
)
from run_parallel_device_matrix import (
    DEFAULT_ANDROID_PORT_BASE,
    DEFAULT_APK,
    DEFAULT_LOCAL_PORT_BASE,
    DEFAULT_RECORD_SECONDS,
    DEFAULT_TIMEOUT_SECONDS,
    MAIN_ACTIVITY,
    PACKAGE_NAME,
    REMOTE_AUTOMATION_PORT,
    S7_SERIAL,
    MatrixConfigError,
    MatrixRunError,
    MatrixTarget,
    android_permissions_for_target,
    apply_settings,
    await_session_value,
    build_android_apk,
    classify_known_blocker,
    collect_android_logcat,
    discover_targets,
    ensure_local_ports_free,
    remove_android_forwards,
    parse_flutter_devices,
    run_command,
    target_to_json,
    write_json,
)

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONNECTION_TIMEOUT_SECONDS = 45.0
DEFAULT_CAPTURE_STAGE_TIMEOUT_SECONDS = 20.0
DEFAULT_RECORDING_READY_TIMEOUT_SECONDS = 12.0
DEFAULT_STOP_RECORDING_TIMEOUT_SECONDS = 25.0
DEFAULT_ROLE_SWITCH_VERIFY_TIMEOUT_SECONDS = 3.0
IMMEDIATE_ROLE_SWITCH_TIMEOUT_SECONDS = 45.0
IMMEDIATE_STANDBY_LAUNCH_TIMEOUT_SECONDS = 10.0
IMMEDIATE_ROLE_SWITCH_VERIFY_TIMEOUT_SECONDS = 8.0
DEFAULT_CONNECTED_CLIENT_POLL_INTERVAL_SECONDS = 0.025
DEFAULT_SESSION_POLL_INTERVAL_SECONDS = 0.5
DEFAULT_IOS_BRIDGE_SCAN_CONNECT_TIMEOUT_SECONDS = 0.5
DEFAULT_IOS_BRIDGE_SCAN_HEALTH_TIMEOUT_SECONDS = 0.8
DEFAULT_IOS_BRIDGE_SCAN_WORKERS = 128
ANDROID_ADB_SETUP_TIMEOUT_SECONDS = 8.0
ANDROID_ADB_LAUNCH_TIMEOUT_SECONDS = 15.0
RUNTIME_ROLE_SWITCH_ACK_MODE = "accepted"
IOS_BUNDLE_ID = "com.keepeyeonball"
IOS_PROFILE_APP = REPO_ROOT / "build" / "ios" / "iphoneos" / "Runner.app"
IOS_PROFILE_APP_FALLBACKS = (
    REPO_ROOT / "build" / "ios" / "Profile-iphoneos" / "Runner.app",
    IOS_PROFILE_APP,
)
MACOS_DEBUG_BINARY = (
    REPO_ROOT
    / "build"
    / "macos"
    / "Build"
    / "Products"
    / "Debug"
    / "HydraCam.app"
    / "Contents"
    / "MacOS"
    / "HydraCam"
)
DEFAULT_LATEST_WARM_SUMMARY = (
    REPO_ROOT
    / "logs"
    / "verification-runs"
    / "latest-rotating-master-slave-warm-summary.json"
)
T = TypeVar("T")


@dataclasses.dataclass(frozen=True)
class MatrixRotation:
    master: MatrixTarget
    clients: list[MatrixTarget]

    @property
    def slug(self) -> str:
        value = f"master-{self.master.platform}-{self.master.device_id}"
        return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-").lower()


class RuntimeRoleSwitchResponses(dict[str, Any]):
    def __init__(
        self,
        responses: Mapping[str, Any],
        *,
        timings: Mapping[str, Any],
        mode: str = "parallel",
    ) -> None:
        super().__init__(responses)
        self.timings = dict(timings)
        self.mode = mode


def now_slug() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M-rotating-master-slave-matrix")


def record_phase_timing(
    phase_timings: MutableMapping[str, Any],
    phase: str,
    *,
    started_at: str,
    elapsed_seconds: float,
) -> None:
    ended_at = dt.datetime.now().isoformat()
    phase_timings[phase] = {
        "startedAt": started_at,
        "endedAt": ended_at,
        "durationMs": round(elapsed_seconds * 1000, 3),
    }


def timed_phase(
    phase_timings: MutableMapping[str, Any],
    phase: str,
    callback: Callable[[], T],
) -> T:
    started_at = dt.datetime.now().isoformat()
    started = time.perf_counter()
    try:
        return callback()
    finally:
        record_phase_timing(
            phase_timings,
            phase,
            started_at=started_at,
            elapsed_seconds=time.perf_counter() - started,
        )


def build_rotations(targets: Sequence[MatrixTarget]) -> list[MatrixRotation]:
    rotations: list[MatrixRotation] = []
    for master in targets:
        if not master.capture_enabled or master.platform == "ios_simulator":
            continue
        clients = [target for target in targets if target.device_id != master.device_id]
        rotations.append(MatrixRotation(master=master, clients=clients))
    return rotations


def filter_targets_by_device_ids(
    targets: Sequence[MatrixTarget],
    device_ids: Sequence[str],
) -> list[MatrixTarget]:
    if not device_ids:
        return list(targets)
    allowed_ids = set(device_ids)
    filtered = [target for target in targets if target.device_id in allowed_ids]
    resolved_ids = {target.device_id for target in filtered}
    missing_ids = sorted(allowed_ids - resolved_ids)
    if missing_ids:
        joined = ", ".join(missing_ids)
        raise MatrixConfigError(f"unknown target-id(s): {joined}")
    return filtered


def _unique_device_ids(device_ids: Sequence[str]) -> list[str]:
    unique: list[str] = []
    seen: set[str] = set()
    for device_id in device_ids:
        normalized = str(device_id).strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        unique.append(normalized)
    return unique


def expected_target_device_actions(device_ids: Sequence[str]) -> list[dict[str, str]]:
    return [
        {
            "deviceId": device_id,
            "code": "expected_target_missing",
            "action": (
                "Connect and unlock this expected device, restore its debug "
                "transport if needed, or remove this --expect-target-id only "
                "for an intentionally scoped run."
            ),
        }
        for device_id in device_ids
    ]


def build_expected_targets_preflight(
    targets: Sequence[MatrixTarget],
    expected_target_ids: Sequence[str],
) -> dict[str, Any]:
    expected_ids = _unique_device_ids(expected_target_ids)
    selected_ids = [target.device_id for target in targets]
    selected_set = set(selected_ids)
    missing_ids = [
        device_id
        for device_id in expected_ids
        if device_id not in selected_set
    ]
    preflight: dict[str, Any] = {
        "status": "failed" if missing_ids else "passed",
        "expectedTargetIds": expected_ids,
        "selectedTargetIds": selected_ids,
        "missingExpectedTargetIds": missing_ids,
    }
    if missing_ids:
        preflight["deviceActions"] = expected_target_device_actions(missing_ids)
    return preflight


def enforce_expected_targets(
    targets: Sequence[MatrixTarget],
    expected_target_ids: Sequence[str],
    run_dir: Path,
) -> None:
    if not expected_target_ids:
        return
    preflight = build_expected_targets_preflight(targets, expected_target_ids)
    write_json(run_dir / "expected-targets.json", preflight)
    missing_ids = preflight["missingExpectedTargetIds"]
    if missing_ids:
        joined = ", ".join(missing_ids)
        raise MatrixRunError(
            f"Expected target-id(s) absent from selected targets: {joined}"
        )


def filter_rotations_by_master_ids(
    rotations: Sequence[MatrixRotation],
    master_ids: Sequence[str],
) -> list[MatrixRotation]:
    if not master_ids:
        return list(rotations)
    allowed_ids = set(master_ids)
    filtered = [
        rotation for rotation in rotations if rotation.master.device_id in allowed_ids
    ]
    resolved_ids = {rotation.master.device_id for rotation in filtered}
    missing_ids = sorted(allowed_ids - resolved_ids)
    if missing_ids:
        joined = ", ".join(missing_ids)
        raise MatrixConfigError(f"unknown master-id(s): {joined}")
    return filtered


def requires_android_apk(targets: Sequence[MatrixTarget]) -> bool:
    return any(target.platform == "android" for target in targets)


def parse_android_wifi_ip(wlan0_output: str, route_output: str) -> str | None:
    wlan_match = re.search(r"\binet\s+((?:\d{1,3}\.){3}\d{1,3})/", wlan0_output)
    if wlan_match:
        return wlan_match.group(1)
    route_match = re.search(r"\bsrc\s+((?:\d{1,3}\.){3}\d{1,3})\b", route_output)
    if route_match:
        return route_match.group(1)
    return None


def build_android_start_command(
    target: MatrixTarget,
    *,
    role: str,
    master_ip: str | None = None,
) -> list[str]:
    command = [
        "adb",
        "-s",
        target.device_id,
        "shell",
        "am",
        "start",
        "-n",
        MAIN_ACTIVITY,
        "--es",
        "role",
        role,
        "--es",
        "automationTargetId",
        target.device_id,
    ]
    if role == "slave":
        if not master_ip:
            raise MatrixConfigError("Android slave launch requires master_ip")
        command.extend(
            [
                "--es",
                "preferredMasterIp",
                master_ip,
                "--ez",
                "forceSlaveMode",
                "true",
            ]
        )
    return command


def build_dry_run_summary(
    targets: Sequence[MatrixTarget],
    rotations: Sequence[MatrixRotation],
    *,
    runtime_role_switch: bool = False,
    role_switch_only: bool = False,
    repeat_role_switch_cycles: int = 1,
) -> dict[str, Any]:
    return {
        "status": "dry_run",
        "sharedBarrierPerRotation": True,
        "runtimeRoleSwitch": runtime_role_switch,
        "roleSwitchOnly": role_switch_only,
        "repeatRoleSwitchCycles": repeat_role_switch_cycles,
        "targetCount": len(targets),
        "captureTargetCount": sum(1 for target in targets if target.capture_enabled),
        "rotationCount": len(rotations) * repeat_role_switch_cycles,
        "targets": [target_to_json(target) for target in targets],
        "rotations": [rotation_to_json(rotation) for rotation in rotations],
    }


def build_phase_timing_stats(
    rotation_results: Sequence[Mapping[str, Any]],
) -> dict[str, dict[str, float | int]]:
    phase_durations: dict[str, list[float]] = {}
    for result in rotation_results:
        phase_timings = result.get("phaseTimings")
        if not isinstance(phase_timings, Mapping):
            continue
        for phase, timing in phase_timings.items():
            if not isinstance(phase, str) or not isinstance(timing, Mapping):
                continue
            duration = timing.get("durationMs")
            if isinstance(duration, (int, float)):
                phase_durations.setdefault(phase, []).append(float(duration))

    return {
        phase: {
            "count": len(durations),
            "minMs": round(min(durations), 3),
            "maxMs": round(max(durations), 3),
            "avgMs": round(sum(durations) / len(durations), 3),
        }
        for phase, durations in sorted(phase_durations.items())
        if durations
    }


def build_runtime_role_switch_timing_stats(
    rotation_results: Sequence[Mapping[str, Any]],
) -> dict[str, dict[str, float | int]]:
    metric_values: dict[str, list[float]] = {
        "parallelRequestStartSkewMs": [],
        "requestStartSkewMs": [],
        "requestEndSkewMs": [],
        "maxRequestDurationMs": [],
    }
    for result in rotation_results:
        snapshot = result.get("runtimeRoleSwitch")
        if not isinstance(snapshot, Mapping):
            continue
        for key in metric_values:
            value = snapshot.get(key)
            if isinstance(value, (int, float)):
                metric_values[key].append(float(value))

    return {
        metric: {
            "count": len(values),
            "minMs": round(min(values), 3),
            "maxMs": round(max(values), 3),
            "avgMs": round(sum(values) / len(values), 3),
        }
        for metric, values in metric_values.items()
        if values
    }


def _parse_iso_datetime(value: Any) -> dt.datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is not None:
        return parsed.astimezone(dt.timezone.utc).replace(tzinfo=None)
    return parsed


def build_connected_client_registration_timing_stats(
    rotation_results: Sequence[Mapping[str, Any]],
) -> dict[str, dict[str, float | int]]:
    metric_values: dict[str, list[float]] = {
        "masterServerStartLagMs": [],
        "latestClientRegistrationLagMs": [],
        "maxClientRegistrationAfterServerStartMs": [],
    }
    for result in rotation_results:
        role_switch = result.get("runtimeRoleSwitch")
        connected_snapshot = result.get("connectedClientsSnapshot")
        if not isinstance(role_switch, Mapping) or not isinstance(
            connected_snapshot,
            Mapping,
        ):
            continue
        switch_started = _parse_iso_datetime(role_switch.get("startedAt"))
        server_started = _parse_iso_datetime(
            connected_snapshot.get("masterServerStartedAt"),
        )
        if switch_started is not None and server_started is not None:
            metric_values["masterServerStartLagMs"].append(
                round(
                    (server_started - switch_started).total_seconds() * 1000,
                    3,
                )
            )

        client_registration_lags: list[float] = []
        client_after_server_lags: list[float] = []
        clients = connected_snapshot.get("connectedClients", [])
        if not isinstance(clients, Sequence) or isinstance(clients, (str, bytes)):
            continue
        for client in clients:
            if not isinstance(client, Mapping):
                continue
            registered_at = _parse_iso_datetime(client.get("registeredAt"))
            if registered_at is None:
                continue
            if switch_started is not None:
                client_registration_lags.append(
                    (registered_at - switch_started).total_seconds() * 1000
                )
            if server_started is not None:
                client_after_server_lags.append(
                    (registered_at - server_started).total_seconds() * 1000
                )
        if client_registration_lags:
            metric_values["latestClientRegistrationLagMs"].append(
                round(max(client_registration_lags), 3),
            )
        if client_after_server_lags:
            metric_values["maxClientRegistrationAfterServerStartMs"].append(
                round(max(client_after_server_lags), 3),
            )

    return {
        metric: {
            "count": len(values),
            "minMs": round(min(values), 3),
            "maxMs": round(max(values), 3),
            "avgMs": round(sum(values) / len(values), 3),
        }
        for metric, values in metric_values.items()
        if values
    }


def _argv_has_option(argv: Sequence[str], name: str) -> bool:
    return any(token == name or token.startswith(f"{name}=") for token in argv)


def _apply_auto_skip_build(args: argparse.Namespace) -> None:
    if not getattr(args, "_hydracam_explicit_skip_build", False):
        args.skip_build = True
        args._hydracam_auto_skip_build = True


def _apply_auto_skip_install(args: argparse.Namespace) -> None:
    if not getattr(args, "_hydracam_explicit_skip_install", False):
        args.skip_install = True
        args._hydracam_auto_skip_install = True


def apply_immediate_role_switch_defaults(
    args: argparse.Namespace,
    *,
    argv: Sequence[str] = (),
) -> argparse.Namespace:
    if not (
        getattr(args, "immediate_role_switch", False)
        or getattr(args, "prime_then_immediate_role_switch", False)
    ):
        return args
    args.runtime_role_switch = True
    args.role_switch_only = True
    args.reuse_running_bridges = True
    args.require_warm_bridges = True
    if hasattr(args, "stage_slaves_after_master_ready") and not getattr(
        args,
        "fully_parallel_role_switch",
        False,
    ):
        args.stage_slaves_after_master_ready = True
    if (
        getattr(args, "warm_summary", None) is None
        and getattr(args, "use_latest_warm_summary", None) is None
    ):
        args._hydracam_auto_use_latest_warm_summary = True
    _apply_auto_skip_build(args)
    _apply_auto_skip_install(args)
    explicit_no_auto_ios = (
        _argv_has_option(argv, "--no-auto-ios-bridge-hosts")
        or getattr(args, "_hydracam_explicit_no_auto_ios_bridge_hosts", False)
    )
    if hasattr(args, "auto_ios_bridge_hosts") and not explicit_no_auto_ios:
        args.auto_ios_bridge_hosts = True
        if not _argv_has_option(argv, "--auto-ios-bridge-hosts") and not getattr(
            args,
            "_hydracam_explicit_auto_ios_bridge_hosts",
            False,
        ):
            args._hydracam_auto_ios_bridge_hosts = True
    if not _argv_has_option(argv, "--timeout"):
        args.timeout = IMMEDIATE_ROLE_SWITCH_TIMEOUT_SECONDS
    if not _argv_has_option(argv, "--standby-launch-timeout"):
        args.standby_launch_timeout = IMMEDIATE_STANDBY_LAUNCH_TIMEOUT_SECONDS
    if not _argv_has_option(argv, "--role-switch-verify-timeout"):
        args.role_switch_verify_timeout = IMMEDIATE_ROLE_SWITCH_VERIFY_TIMEOUT_SECONDS
    return args


def apply_warm_prime_defaults(args: argparse.Namespace) -> argparse.Namespace:
    if not (
        getattr(args, "warm_prime_only", False)
        or getattr(args, "prime_then_immediate_role_switch", False)
    ):
        return args
    args.runtime_role_switch = True
    args.role_switch_only = True
    args.reuse_running_bridges = True
    if (
        getattr(args, "warm_summary", None) is None
        and getattr(args, "use_latest_warm_summary", None) is None
    ):
        args._hydracam_auto_use_latest_warm_summary = True
    _apply_auto_skip_build(args)
    _apply_auto_skip_install(args)
    return args


def should_build_ios_profile_app(args: argparse.Namespace) -> bool:
    if not getattr(args, "ios_profile_build_install", False):
        return False
    if not getattr(args, "skip_build", False):
        return True
    return bool(getattr(args, "_hydracam_auto_skip_build", False))


def should_install_ios_profile_app(args: argparse.Namespace) -> bool:
    if not getattr(args, "ios_profile_build_install", False):
        return False
    if not getattr(args, "skip_install", False):
        return True
    return bool(getattr(args, "_hydracam_auto_skip_install", False))


def build_runtime_role_payloads(
    rotation: MatrixRotation,
    *,
    master_host: str,
) -> dict[str, dict[str, Any]]:
    payloads = {
        rotation.master.device_id: {
            "role": "master",
        }
    }
    for client in rotation.clients:
        payloads[client.device_id] = {
            "role": "slave",
            "preferredMasterIp": master_host,
            "forceSlaveMode": True,
            "ackMode": RUNTIME_ROLE_SWITCH_ACK_MODE,
        }
    return payloads


def rotation_to_json(rotation: MatrixRotation) -> dict[str, Any]:
    return {
        "master": target_to_json(rotation.master),
        "masterDeviceId": rotation.master.device_id,
        "knownBlocker": rotation.master.known_blocker,
        "clientDeviceIds": [client.device_id for client in rotation.clients],
        "clientCount": len(rotation.clients),
    }


def write_summary_markdown(run_dir: Path, summary: Mapping[str, Any]) -> None:
    lines = [
        "# Rotating Master/Slave Matrix",
        "",
        f"- Status: `{summary.get('status')}`",
        f"- Shared barrier per rotation: `{summary.get('sharedBarrierPerRotation')}`",
        f"- Rotation count: `{summary.get('rotationCount')}`",
        f"- Repeat role-switch cycles: `{summary.get('repeatRoleSwitchCycles', 1)}`",
    ]
    if summary.get("elapsedSeconds") is not None:
        lines.append(f"- Elapsed seconds: `{summary.get('elapsedSeconds')}`")
    phase_stats = summary.get("phaseTimingStats")
    if isinstance(phase_stats, Mapping) and phase_stats:
        lines.extend([
            "",
            "| Phase | Count | Min ms | Avg ms | Max ms |",
            "| --- | ---: | ---: | ---: | ---: |",
        ])
        for phase, stats in phase_stats.items():
            if not isinstance(stats, Mapping):
                continue
            lines.append(
                f"| `{phase}` | `{stats.get('count')}` | "
                f"`{stats.get('minMs')}` | `{stats.get('avgMs')}` | "
                f"`{stats.get('maxMs')}` |"
            )
    role_switch_stats = summary.get("runtimeRoleSwitchTimingStats")
    if isinstance(role_switch_stats, Mapping) and role_switch_stats:
        lines.extend([
            "",
            "| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |",
            "| --- | ---: | ---: | ---: | ---: |",
        ])
        for metric, stats in role_switch_stats.items():
            if not isinstance(stats, Mapping):
                continue
            lines.append(
                f"| `{metric}` | `{stats.get('count')}` | "
                f"`{stats.get('minMs')}` | `{stats.get('avgMs')}` | "
                f"`{stats.get('maxMs')}` |"
            )
    registration_stats = summary.get("connectedClientRegistrationTimingStats")
    if isinstance(registration_stats, Mapping) and registration_stats:
        lines.extend([
            "",
            "| Client Registration Metric | Count | Min ms | Avg ms | Max ms |",
            "| --- | ---: | ---: | ---: | ---: |",
        ])
        for metric, stats in registration_stats.items():
            if not isinstance(stats, Mapping):
                continue
            lines.append(
                f"| `{metric}` | `{stats.get('count')}` | "
                f"`{stats.get('minMs')}` | `{stats.get('avgMs')}` | "
                f"`{stats.get('maxMs')}` |"
            )
    lines.extend([
        "",
        "| Master | Status | Clients | Notes |",
        "| --- | --- | --- | --- |",
    ])
    for rotation in summary.get("rotations", []):
        if not isinstance(rotation, Mapping):
            continue
        master = rotation.get("master", {})
        if not isinstance(master, Mapping):
            master = {}
        master_id = rotation.get("masterDeviceId") or master.get("deviceId", "")
        status = rotation.get("status", "pending")
        clients = ", ".join(f"`{entry}`" for entry in rotation.get("clientDeviceIds", []))
        failures = rotation.get("failures", [])
        notes = rotation.get("knownBlocker") or "; ".join(failures)
        lines.append(f"| `{master_id}` | `{status}` | {clients} | {notes} |")
    (run_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def discover_android_master_host(target: MatrixTarget) -> str:
    wlan0 = run_command(
        ["adb", "-s", target.device_id, "shell", "ip", "-f", "inet", "addr", "show", "wlan0"],
        check=False,
        capture_output=True,
        timeout=10,
    )
    route = run_command(
        ["adb", "-s", target.device_id, "shell", "ip", "route", "get", "1.1.1.1"],
        check=False,
        capture_output=True,
        timeout=10,
    )
    ip_address = parse_android_wifi_ip(wlan0.stdout or "", route.stdout or "")
    if not ip_address:
        raise MatrixRunError(f"Could not resolve Wi-Fi IP for Android master {target.device_id}")
    return ip_address


def discover_macos_master_host() -> str:
    for interface in ("en0", "en1"):
        result = run_command(
            ["ipconfig", "getifaddr", interface],
            check=False,
            capture_output=True,
            timeout=5,
        )
        host = (result.stdout or "").strip()
        if host:
            return host
    hostname_result = run_command(
        ["hostname", "-I"],
        check=False,
        capture_output=True,
        timeout=5,
    )
    for candidate in (hostname_result.stdout or "").split():
        if candidate.startswith(("10.", "172.", "192.168.")):
            return candidate
    raise MatrixRunError("Could not resolve a local Wi-Fi IP for macOS master")


def resolve_master_hosts(
    targets: Sequence[MatrixTarget],
    *,
    macos_master_host: str | None,
) -> dict[str, str]:
    hosts: dict[str, str] = {}
    for target in targets:
        if target.platform == "ios_physical":
            hosts[target.device_id] = target.host
        elif target.platform == "android" and target.capture_enabled:
            hosts[target.device_id] = discover_android_master_host(target)
        elif target.platform == "macos":
            hosts[target.device_id] = macos_master_host or discover_macos_master_host()
    return hosts


def _summary_path(path: Path) -> Path:
    if not path.is_dir():
        return path
    summary_path = path / "summary.json"
    if summary_path.exists():
        return summary_path
    return path / "warm-bridge-prime.json"


def _target_from_summary(payload: Mapping[str, Any]) -> MatrixTarget:
    bridge_url = str(payload.get("bridgeUrl", ""))
    parsed = urllib.parse.urlparse(bridge_url)
    if parsed.scheme != "http" or not parsed.hostname or parsed.port is None:
        raise MatrixConfigError(f"Invalid bridgeUrl in warm summary: {bridge_url!r}")
    return MatrixTarget(
        device_id=str(payload["deviceId"]),
        label=str(payload.get("label") or payload["deviceId"]),
        platform=str(payload["platform"]),
        runtime=str(payload.get("runtime") or ""),
        lens=str(payload["lens"]),
        profile=str(payload["profile"]),
        host=parsed.hostname,
        bridge_port=parsed.port,
        capture_enabled=bool(payload["captureEnabled"]),
        expected_result=str(payload["expectedResult"]),
        known_blocker=(
            str(payload["knownBlocker"])
            if payload.get("knownBlocker") is not None
            else None
        ),
    )


def load_warm_summary_targets(path: Path) -> tuple[list[MatrixTarget], dict[str, str]]:
    summary = json.loads(_summary_path(path).read_text(encoding="utf-8"))
    if not isinstance(summary, Mapping):
        raise MatrixConfigError("Warm summary must contain a JSON object")
    raw_targets = summary.get("targets")
    if not isinstance(raw_targets, list):
        raise MatrixConfigError("Warm summary is missing a targets list")
    targets = [
        _target_from_summary(target)
        for target in raw_targets
        if isinstance(target, Mapping)
    ]
    raw_master_hosts = summary.get("masterHosts", {})
    if not isinstance(raw_master_hosts, Mapping):
        raise MatrixConfigError("Warm summary masterHosts must be an object")
    master_hosts = {
        str(device_id): str(host)
        for device_id, host in raw_master_hosts.items()
    }
    return targets, master_hosts


def resolve_warm_summary_path(args: argparse.Namespace, run_dir: Path) -> Path | None:
    explicit_summary = getattr(args, "warm_summary", None)
    if explicit_summary is not None:
        path = _summary_path(explicit_summary)
        if not path.exists():
            raise MatrixConfigError(f"Warm summary does not exist: {path}")
        write_json(
            run_dir / "warm-summary-source.json",
            {
                "status": "used",
                "mode": "explicit",
                "path": str(path),
            },
        )
        return path

    explicit_latest = getattr(args, "use_latest_warm_summary", None) is True
    auto_latest = bool(
        getattr(args, "_hydracam_auto_use_latest_warm_summary", False),
    )
    latest_summary_value = getattr(args, "latest_warm_summary", None)
    latest_summary = Path(latest_summary_value) if latest_summary_value else None
    if explicit_latest:
        if latest_summary is None:
            raise MatrixConfigError("--use-latest-warm-summary requires a cache path")
        if not latest_summary.exists():
            raise MatrixConfigError(
                f"Latest warm summary does not exist: {latest_summary}"
            )
        write_json(
            run_dir / "warm-summary-source.json",
            {
                "status": "used",
                "mode": "latest",
                "path": str(latest_summary),
            },
        )
        args._hydracam_used_latest_warm_summary = True
        return latest_summary
    if auto_latest:
        if latest_summary is not None and latest_summary.exists():
            args._hydracam_used_auto_latest_warm_summary = True
            args._hydracam_used_latest_warm_summary = True
            write_json(
                run_dir / "warm-summary-source.json",
                {
                    "status": "used",
                    "mode": "auto_latest",
                    "path": str(latest_summary),
                },
            )
            return latest_summary
        write_json(
            run_dir / "warm-summary-source.json",
            {
                "status": "not_used",
                "mode": "auto_latest",
                "reason": (
                    "latest_warm_summary_missing"
                    if latest_summary is not None
                    else "latest_warm_summary_path_not_configured"
                ),
                "path": str(latest_summary) if latest_summary is not None else None,
            },
        )
    return None


def missing_master_host_device_ids(
    targets: Sequence[MatrixTarget],
    master_hosts: Mapping[str, str],
) -> list[str]:
    return [
        target.device_id
        for target in targets
        if target.capture_enabled
        and target.platform != "ios_simulator"
        and target.device_id not in master_hosts
    ]


def write_latest_warm_summary_cache(
    args: argparse.Namespace,
    run_dir: Path,
    *,
    targets: Sequence[MatrixTarget],
    master_hosts: Mapping[str, str] | None,
    source_artifact: Path,
) -> None:
    if not getattr(args, "update_latest_warm_summary", True):
        write_json(
            run_dir / "latest-warm-summary-cache.json",
            {
                "status": "skipped",
                "reason": "disabled",
            },
        )
        return
    if master_hosts is None:
        write_json(
            run_dir / "latest-warm-summary-cache.json",
            {
                "status": "skipped",
                "reason": "missing_master_hosts",
            },
        )
        return
    missing_hosts = missing_master_host_device_ids(targets, master_hosts)
    if missing_hosts:
        write_json(
            run_dir / "latest-warm-summary-cache.json",
            {
                "status": "skipped",
                "reason": "missing_master_hosts",
                "missingMasterHostDeviceIds": missing_hosts,
            },
        )
        return

    latest_summary_value = getattr(args, "latest_warm_summary", None)
    if not latest_summary_value:
        write_json(
            run_dir / "latest-warm-summary-cache.json",
            {
                "status": "skipped",
                "reason": "latest_warm_summary_path_not_configured",
            },
        )
        return
    latest_summary = Path(latest_summary_value)
    payload = {
        "schema": "hydracam.rotatingMasterSlave.latestWarmSummary.v1",
        "generatedAt": dt.datetime.now().isoformat(),
        "sourceRunDir": str(run_dir),
        "sourceArtifact": str(source_artifact),
        "targets": [target_to_json(target) for target in targets],
        "masterHosts": dict(master_hosts),
    }
    write_json(latest_summary, payload)
    write_json(
        run_dir / "latest-warm-summary-cache.json",
        {
            "status": "updated",
            "path": str(latest_summary),
            "targetCount": len(targets),
            "masterHostDeviceIds": sorted(master_hosts),
        },
    )


def _is_physical_ios_flutter_device(device: Any) -> bool:
    return (
        getattr(device, "platform", None) == "ios"
        and "simulator" not in str(getattr(device, "runtime", "")).lower()
    )


def _normalize_bridge_host(value: str) -> str | None:
    stripped = value.strip()
    if not stripped:
        return None
    if "://" in stripped:
        parsed = urllib.parse.urlparse(stripped)
        return parsed.hostname
    if stripped.count(":") == 1:
        host, port = stripped.rsplit(":", 1)
        if port.isdigit():
            return host
    return stripped


def _explicit_ios_host_map(entries: Sequence[str]) -> dict[str, str]:
    hosts: dict[str, str] = {}
    for entry in entries:
        if "=" not in entry:
            continue
        device_id, host = entry.split("=", 1)
        normalized = _normalize_bridge_host(host)
        if device_id.strip() and normalized and normalized != "auto":
            hosts[device_id.strip()] = normalized
    return hosts


def parse_arp_ipv4_hosts(output: str) -> list[str]:
    hosts: list[str] = []
    seen: set[str] = set()
    for match in re.finditer(r"(?:\((?P<paren>\d+(?:\.\d+){3})\)|\b(?P<plain>\d+(?:\.\d+){3})\b)", output):
        value = match.group("paren") or match.group("plain")
        try:
            address = ipaddress.ip_address(value)
        except ValueError:
            continue
        if address.version != 4 or address.is_loopback or address.is_multicast:
            continue
        host = str(address)
        if host not in seen:
            seen.add(host)
            hosts.append(host)
    return hosts


def _local_ipv4_subnets() -> list[str]:
    subnets: list[str] = []
    seen: set[str] = set()
    for interface in ("en0", "en1", "en2", "bridge100"):
        result = subprocess.run(
            ["ipconfig", "getifaddr", interface],
            cwd=REPO_ROOT,
            check=False,
            text=True,
            capture_output=True,
            timeout=2,
        )
        host = (result.stdout or "").strip()
        if not host:
            continue
        try:
            network = ipaddress.ip_network(f"{host}/24", strict=False)
        except ValueError:
            continue
        value = str(network)
        if value not in seen:
            seen.add(value)
            subnets.append(value)
    return subnets


def _subnet_hosts(subnet: str) -> list[str]:
    try:
        network = ipaddress.ip_network(subnet, strict=False)
    except ValueError:
        return []
    return [str(host) for host in network.hosts()]


def _candidate_ios_bridge_hosts(
    args: argparse.Namespace,
    targets: Sequence[MatrixTarget] = (),
) -> list[str]:
    hosts: list[str] = []
    seen: set[str] = set()

    def add(host: str | None) -> None:
        normalized = _normalize_bridge_host(host or "")
        if not normalized or normalized in {"127.0.0.1", "localhost"}:
            return
        try:
            address = ipaddress.ip_address(normalized)
            if address.version != 4 or address.is_loopback or address.is_multicast:
                return
        except ValueError:
            pass
        if normalized not in seen:
            seen.add(normalized)
            hosts.append(normalized)

    for target in targets:
        if target.platform == "ios_physical":
            add(target.host)
    for host in _explicit_ios_host_map(getattr(args, "ios_host", [])).values():
        add(host)

    arp_result = subprocess.run(
        ["arp", "-an"],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
        timeout=3,
    )
    for host in parse_arp_ipv4_hosts(arp_result.stdout or ""):
        add(host)

    scan_subnets = [
        *getattr(args, "ios_bridge_scan_subnet", []),
        *_local_ipv4_subnets(),
    ]
    for subnet in scan_subnets:
        for host in _subnet_hosts(subnet):
            add(host)
    return hosts


def _tcp_port_is_open(host: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def discover_running_ios_bridge_hosts(
    device_ids: Sequence[str],
    *,
    hosts: Sequence[str],
    port: int,
    connect_timeout: float = DEFAULT_IOS_BRIDGE_SCAN_CONNECT_TIMEOUT_SECONDS,
    health_timeout: float = DEFAULT_IOS_BRIDGE_SCAN_HEALTH_TIMEOUT_SECONDS,
) -> dict[str, dict[str, Any]]:
    expected_ids = set(device_ids)
    matches: dict[str, dict[str, Any]] = {}
    candidates = list(dict.fromkeys(hosts))
    if not expected_ids or not candidates:
        return matches

    def probe(host: str) -> tuple[str, dict[str, Any]] | None:
        if not _tcp_port_is_open(host, port, connect_timeout):
            return None
        bridge_url = f"http://{host}:{port}"
        try:
            health = request_json(bridge_url, "GET", "/healthz", timeout=health_timeout)
        except ReproError:
            return None
        if not _bridge_health_supports_role_switch(health):
            return None
        device_id = str(health.get("automationTargetId", ""))
        if device_id not in expected_ids:
            return None
        return device_id, {
            "deviceId": device_id,
            "host": host,
            "bridgeUrl": bridge_url,
            "health": health,
        }

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=min(DEFAULT_IOS_BRIDGE_SCAN_WORKERS, max(1, len(candidates))),
    ) as executor:
        futures = [executor.submit(probe, host) for host in candidates]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result is None:
                continue
            device_id, match = result
            matches.setdefault(device_id, match)
    return matches


def wait_for_running_ios_bridge_hosts(
    device_ids: Sequence[str],
    args: argparse.Namespace,
    *,
    deadline: float,
) -> dict[str, dict[str, Any]]:
    matches: dict[str, dict[str, Any]] = {}
    while time.time() < deadline:
        candidates = _candidate_ios_bridge_hosts(args)
        matches = discover_running_ios_bridge_hosts(
            device_ids,
            hosts=candidates,
            port=getattr(args, "physical_ios_port", DEFAULT_PORT),
        )
        if set(device_ids) <= set(matches):
            return matches
        time.sleep(0.5)
    return matches


def fast_launch_ios_for_host_discovery(
    device: Any,
    args: argparse.Namespace,
    run_dir: Path,
) -> dict[str, Any]:
    target = MatrixTarget(
        device_id=device.device_id,
        label=device.label,
        platform="ios_physical",
        runtime=device.runtime,
        lens="autoBack",
        profile="standard1080p30",
        host="127.0.0.1",
        bridge_port=getattr(args, "physical_ios_port", DEFAULT_PORT),
        capture_enabled=True,
        expected_result="capture",
    )
    target_dir = run_dir / "ios-auto-host-fast-launch" / target.slug
    target_dir.mkdir(parents=True, exist_ok=True)
    result = run_command(
        build_ios_fast_launch_command(target, role="standby", master_ip=None),
        check=False,
        capture_output=True,
        timeout=45,
    )
    (target_dir / "fast-ios-launch.stdout.txt").write_text(
        result.stdout or "",
        encoding="utf-8",
    )
    (target_dir / "fast-ios-launch.stderr.txt").write_text(
        result.stderr or "",
        encoding="utf-8",
    )
    return {
        "deviceId": device.device_id,
        "returnCode": result.returncode,
        "stdoutPath": str(target_dir / "fast-ios-launch.stdout.txt"),
        "stderrPath": str(target_dir / "fast-ios-launch.stderr.txt"),
    }


def prefill_ios_hosts_from_running_bridges(
    args: argparse.Namespace,
    run_dir: Path,
) -> None:
    if not getattr(args, "auto_ios_bridge_hosts", False):
        return
    explicit_hosts = _explicit_ios_host_map(getattr(args, "ios_host", []))
    flutter_output = run_command(
        ["flutter", "devices"],
        capture_output=True,
    ).stdout
    selected_ids = set(getattr(args, "target_id", []) or [])
    physical_ios_devices = [
        device
        for device in parse_flutter_devices(flutter_output)
        if _is_physical_ios_flutter_device(device)
        and (not selected_ids or device.device_id in selected_ids)
    ]
    missing_ids = [
        device.device_id
        for device in physical_ios_devices
        if device.device_id not in explicit_hosts
    ]
    candidates = _candidate_ios_bridge_hosts(args)
    matches = discover_running_ios_bridge_hosts(
        missing_ids,
        hosts=candidates,
        port=getattr(args, "physical_ios_port", DEFAULT_PORT),
    )
    launch_results: list[dict[str, Any]] = []
    launch_missing_ids = sorted(set(missing_ids) - set(matches))
    if (
        launch_missing_ids
        and getattr(args, "fast_ios_launch", False)
        and (
            getattr(args, "warm_prime_only", False)
            or getattr(args, "prime_then_immediate_role_switch", False)
        )
    ):
        devices_by_id = {device.device_id: device for device in physical_ios_devices}
        for device_id in launch_missing_ids:
            device = devices_by_id.get(device_id)
            if device is None:
                continue
            launch_results.append(
                fast_launch_ios_for_host_discovery(device, args, run_dir),
            )
        matches = wait_for_running_ios_bridge_hosts(
            missing_ids,
            args,
            deadline=time.time()
            + float(
                getattr(args, "standby_launch_timeout", None)
                or getattr(args, "timeout", IMMEDIATE_STANDBY_LAUNCH_TIMEOUT_SECONDS)
            ),
        )
    new_entries = [
        f"{device_id}={match['host']}"
        for device_id, match in sorted(matches.items())
    ]
    if new_entries:
        args.ios_host = [*getattr(args, "ios_host", []), *new_entries]
    write_json(
        run_dir / "ios-bridge-host-prefill.json",
        {
            "status": "passed" if len(matches) == len(missing_ids) else "partial",
            "physicalIosDeviceIds": [device.device_id for device in physical_ios_devices],
            "explicitIosHostDeviceIds": sorted(explicit_hosts),
            "missingIosHostDeviceIds": missing_ids,
            "matchedIosHostDeviceIds": sorted(matches),
            "candidateHostCount": len(candidates),
            "fastLaunchAttemptedDeviceIds": [
                result["deviceId"] for result in launch_results
            ],
            "fastLaunchResults": launch_results,
            "matches": matches,
        },
    )


def adopt_running_ios_bridge_hosts(
    targets: Sequence[MatrixTarget],
    args: argparse.Namespace,
    run_dir: Path,
) -> tuple[list[MatrixTarget], dict[str, dict[str, Any]]]:
    if not getattr(args, "auto_ios_bridge_hosts", False):
        return list(targets), {}
    ios_targets = [target for target in targets if target.platform == "ios_physical"]
    if not ios_targets:
        return list(targets), {}
    candidates = _candidate_ios_bridge_hosts(args, ios_targets)
    matches = discover_running_ios_bridge_hosts(
        [target.device_id for target in ios_targets],
        hosts=candidates,
        port=getattr(args, "physical_ios_port", DEFAULT_PORT),
    )
    updated_targets = [
        dataclasses.replace(target, host=str(matches[target.device_id]["host"]))
        if target.platform == "ios_physical" and target.device_id in matches
        else target
        for target in targets
    ]
    write_json(
        run_dir / "ios-bridge-host-adoption.json",
        {
            "status": "passed" if len(matches) == len(ios_targets) else "partial",
            "physicalIosDeviceIds": [target.device_id for target in ios_targets],
            "matchedIosHostDeviceIds": sorted(matches),
            "candidateHostCount": len(candidates),
            "matches": matches,
            "targets": [target_to_json(target) for target in updated_targets],
        },
    )
    return updated_targets, matches


def _local_bridge_target(target: MatrixTarget) -> bool:
    return target.host in {"127.0.0.1", "localhost"}


def _bridge_health_supports_role_switch(health: Mapping[str, Any]) -> bool:
    commands = health.get("commands", [])
    return (
        health.get("status") == "ok"
        and isinstance(commands, list)
        and "set_role" in commands
        and isinstance(health.get("automationTargetId"), str)
    )


def _running_bridge_identities(ports: Sequence[int]) -> dict[str, int]:
    identities: dict[str, int] = {}
    for port in sorted(set(ports)):
        try:
            health = request_json(
                f"http://127.0.0.1:{port}",
                "GET",
                "/healthz",
                timeout=0.4,
            )
        except ReproError:
            continue
        if not _bridge_health_supports_role_switch(health):
            continue
        device_id = str(health["automationTargetId"])
        identities.setdefault(device_id, port)
    return identities


def _first_available_port(candidates: Sequence[int], used_ports: set[int]) -> int:
    for port in candidates:
        if port not in used_ports:
            return port
    port = max(candidates, default=0) + 1
    while port in used_ports:
        port += 1
    return port


def adopt_running_bridge_ports(
    targets: Sequence[MatrixTarget],
    *,
    android_port_base: int,
    local_port_base: int,
) -> list[MatrixTarget]:
    local_targets = [target for target in targets if _local_bridge_target(target)]
    android_targets = [target for target in local_targets if target.platform == "android"]
    desktop_targets = [
        target
        for target in local_targets
        if target.platform in {"macos", "ios_simulator"}
    ]
    android_pool = list(
        range(android_port_base, android_port_base + max(len(android_targets) + 4, 8))
    )
    desktop_pool = [DEFAULT_PORT, *range(local_port_base, local_port_base + max(len(desktop_targets) + 4, 8))]
    scan_ports = {
        target.bridge_port
        for target in local_targets
    } | set(android_pool) | set(desktop_pool)
    running_ports_by_id = _running_bridge_identities(sorted(scan_ports))
    used_ports: set[int] = set()
    adopted: list[MatrixTarget | None] = [None] * len(targets)

    for index, target in enumerate(targets):
        if not _local_bridge_target(target):
            adopted[index] = target
            continue
        running_port = running_ports_by_id.get(target.device_id)
        if running_port is not None:
            adopted[index] = dataclasses.replace(target, bridge_port=running_port)
            used_ports.add(running_port)

    for index, target in enumerate(targets):
        if adopted[index] is not None:
            continue
        if not _local_bridge_target(target):
            adopted[index] = target
            continue
        if target.platform == "android":
            candidates = [target.bridge_port, *android_pool]
        else:
            candidates = [target.bridge_port, *desktop_pool]
        bridge_port = (
            target.bridge_port
            if target.bridge_port not in used_ports
            else _first_available_port(candidates, used_ports)
        )
        adopted[index] = dataclasses.replace(target, bridge_port=bridge_port)
        used_ports.add(bridge_port)

    return [target for target in adopted if target is not None]


def normalize_direct_macos_bridge_ports(
    targets: Sequence[MatrixTarget],
) -> list[MatrixTarget]:
    return [
        dataclasses.replace(target, bridge_port=DEFAULT_PORT)
        if target.platform == "macos"
        else target
        for target in targets
    ]


def prepare_android_target(
    target: MatrixTarget,
    apk: Path,
    *,
    skip_install: bool,
    reuse_running_bridge: bool = False,
) -> None:
    if not skip_install:
        run_command(["adb", "-s", target.device_id, "install", "-r", str(apk)])
    if reuse_running_bridge and bridge_supports_runtime_role_switch(target):
        return
    run_command(
        [
            "adb",
            "-s",
            target.device_id,
            "forward",
            f"tcp:{target.bridge_port}",
            f"tcp:{REMOTE_AUTOMATION_PORT}",
        ]
    )
    if reuse_running_bridge and bridge_supports_runtime_role_switch(target):
        return
    for permission in android_permissions_for_target(target):
        try:
            run_command(
                [
                    "adb",
                    "-s",
                    target.device_id,
                    "shell",
                    "pm",
                    "grant",
                    PACKAGE_NAME,
                    permission,
                ],
                check=False,
                timeout=ANDROID_ADB_SETUP_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired:
            print(
                (
                    "warning: timed out granting "
                    f"{permission} on {target.device_id}; continuing"
                ),
                flush=True,
            )


def stop_android_target(target: MatrixTarget) -> None:
    if target.platform == "android":
        try:
            run_command(
                ["adb", "-s", target.device_id, "shell", "am", "force-stop", PACKAGE_NAME],
                check=False,
                timeout=ANDROID_ADB_SETUP_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired:
            print(
                f"warning: timed out force-stopping {PACKAGE_NAME} on {target.device_id}; continuing",
                flush=True,
            )


def launch_android_target(
    target: MatrixTarget,
    *,
    role: str,
    master_ip: str | None,
) -> None:
    stop_android_target(target)
    try:
        run_command(
            build_android_start_command(target, role=role, master_ip=master_ip),
            timeout=ANDROID_ADB_LAUNCH_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise MatrixRunError(
            (
                "Timed out launching Android target "
                f"{target.device_id} after {ANDROID_ADB_LAUNCH_TIMEOUT_SECONDS:.0f}s"
            )
        ) from error


def launch_flutter_target(
    target: MatrixTarget,
    rotation_dir: Path,
    *,
    role: str,
    master_ip: str | None,
    timeout: float,
) -> None:
    target_dir = rotation_dir / target.slug
    target_dir.mkdir(parents=True, exist_ok=True)
    process = launch_flutter(
        target.device_id,
        target_dir / "flutter-run.log",
        port=target.bridge_port,
        role=role,
        master_ip=master_ip,
    )
    try:
        wait_for_flutter_bridge(target, process, time.time() + timeout)
    except Exception:
        stop_flutter(process)
        raise
    detach_flutter(process)
    return None


def launch_macos_standby_target(
    target: MatrixTarget,
    rotation_dir: Path,
    *,
    timeout: float,
) -> subprocess.Popen[str]:
    if not MACOS_DEBUG_BINARY.exists():
        raise MatrixRunError(
            "macOS debug app is not built. Run `flutter build macos --debug "
            "--dart-define=HYDRACAM_AUTOMATION=true` first."
        )
    target_dir = rotation_dir / target.slug
    target_dir.mkdir(parents=True, exist_ok=True)
    log_handle = (target_dir / "macos-app.log").open("w", encoding="utf-8")
    process = subprocess.Popen(
        [str(MACOS_DEBUG_BINARY)],
        cwd=REPO_ROOT,
        env={
            **os.environ,
            "HYDRACAM_AUTOMATION_ROLE": "standby",
            "HYDRACAM_AUTOMATION_TARGET_ID": target.device_id,
        },
        stdin=subprocess.PIPE,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    process._hydracam_log_handle = log_handle  # type: ignore[attr-defined]
    wait_for_target_bridge(target, time.time() + timeout)
    return process


def build_ios_fast_launch_command(
    target: MatrixTarget,
    *,
    role: str,
    master_ip: str | None,
) -> list[str]:
    environment = {
        "HYDRACAM_AUTOMATION_ROLE": role,
        "HYDRACAM_AUTOMATION_TARGET_ID": target.device_id,
    }
    if master_ip:
        environment["HYDRACAM_AUTOMATION_MASTER_IP"] = master_ip
    if role == "slave":
        environment["HYDRACAM_AUTOMATION_FORCE_SLAVE"] = "true"
    return [
        "xcrun",
        "devicectl",
        "device",
        "process",
        "launch",
        "--device",
        target.device_id,
        "--terminate-existing",
        "--environment-variables",
        json.dumps(environment, sort_keys=True),
        IOS_BUNDLE_ID,
    ]


def _ios_launch_environment(
    target: MatrixTarget,
    *,
    role: str,
    master_ip: str | None,
) -> dict[str, str]:
    environment = {
        "HYDRACAM_AUTOMATION_ROLE": role,
        "HYDRACAM_AUTOMATION_TARGET_ID": target.device_id,
    }
    if master_ip:
        environment["HYDRACAM_AUTOMATION_MASTER_IP"] = master_ip
    if role == "slave":
        environment["HYDRACAM_AUTOMATION_FORCE_SLAVE"] = "true"
    return environment


def build_ios_xctrace_launch_command(
    target: MatrixTarget,
    *,
    role: str,
    master_ip: str | None,
    output: Path,
    time_limit_seconds: int,
) -> list[str]:
    command = [
        "xcrun",
        "xctrace",
        "record",
        "--template",
        "Time Profiler",
        "--device",
        target.device_id,
        "--time-limit",
        f"{time_limit_seconds}s",
        "--output",
        str(output),
    ]
    for key, value in sorted(
        _ios_launch_environment(
            target,
            role=role,
            master_ip=master_ip,
        ).items()
    ):
        command.extend(["--env", f"{key}={value}"])
    command.extend(["--launch", "--", IOS_BUNDLE_ID])
    return command


def classify_ios_xctrace_launch_error(stderr: str) -> str:
    lowered = stderr.lower()
    if (
        "invalid code signature" in lowered
        or "inadequate entitlements" in lowered
        or "profile has not been explicitly trusted" in lowered
    ):
        return (
            "ios_profile_not_trusted: the installed HydraCam build could not "
            "launch because its signing profile is not trusted on the device."
        )
    return stderr.strip() or "xctrace launch failed"


def launch_ios_fast_target(
    target: MatrixTarget,
    rotation_dir: Path,
    *,
    role: str,
    master_ip: str | None,
    timeout: float,
) -> None:
    target_dir = rotation_dir / target.slug
    target_dir.mkdir(parents=True, exist_ok=True)
    result = run_command(
        build_ios_fast_launch_command(target, role=role, master_ip=master_ip),
        capture_output=True,
        timeout=45,
    )
    (target_dir / "fast-ios-launch.stdout.txt").write_text(
        result.stdout or "",
        encoding="utf-8",
    )
    (target_dir / "fast-ios-launch.stderr.txt").write_text(
        result.stderr or "",
        encoding="utf-8",
    )
    wait_for_target_bridge(target, time.time() + timeout)


def launch_ios_xctrace_target(
    target: MatrixTarget,
    rotation_dir: Path,
    *,
    role: str,
    master_ip: str | None,
    timeout: float,
    time_limit_seconds: int,
) -> subprocess.Popen[str]:
    target_dir = rotation_dir / target.slug
    target_dir.mkdir(parents=True, exist_ok=True)
    stdout_path = target_dir / "xctrace-launch.stdout.txt"
    stderr_path = target_dir / "xctrace-launch.stderr.txt"
    log_handle = stdout_path.open("w", encoding="utf-8")
    error_handle = stderr_path.open("w", encoding="utf-8")
    process = subprocess.Popen(
        build_ios_xctrace_launch_command(
            target,
            role=role,
            master_ip=master_ip,
            output=target_dir / "hydracam-launch.trace",
            time_limit_seconds=time_limit_seconds,
        ),
        cwd=REPO_ROOT,
        stdin=subprocess.PIPE,
        stdout=log_handle,
        stderr=error_handle,
        text=True,
    )
    process._hydracam_log_handle = log_handle  # type: ignore[attr-defined]
    process._hydracam_error_handle = error_handle  # type: ignore[attr-defined]
    deadline = time.time() + timeout
    last_error: Exception | None = None
    last_health: dict[str, Any] = {}
    while time.time() < deadline:
        try:
            last_health = request_json(target.bridge_url, "GET", "/healthz", timeout=3)
            if bridge_health_matches_target(last_health, target):
                return process
        except ReproError as error:
            last_error = error
        if process.poll() is not None:
            log_handle.close()
            error_handle.close()
            stderr = stderr_path.read_text(encoding="utf-8")
            raise ReproError(
                f"xctrace launch for {target.device_id} exited before "
                f"{target.bridge_url}/healthz became reachable: "
                f"{classify_ios_xctrace_launch_error(stderr)}"
            )
        time.sleep(1)
    raise ReproError(
        f"Automation bridge did not become healthy for {target.device_id} "
        f"at {target.bridge_url}: last_health={last_health}, last_error={last_error}"
    )


def wait_for_flutter_bridge(
    target: MatrixTarget,
    process: subprocess.Popen[str],
    deadline: float,
) -> None:
    last_error: Exception | None = None
    last_health: dict[str, Any] = {}
    while time.time() < deadline:
        try:
            last_health = request_json(target.bridge_url, "GET", "/healthz", timeout=3)
            if bridge_health_matches_target(last_health, target):
                return
        except ReproError as error:
            last_error = error
        if process.poll() is not None:
            raise ReproError(
                f"flutter run for {target.device_id} exited before "
                f"{target.bridge_url}/healthz became reachable: {last_error}"
            )
        time.sleep(1)
    raise ReproError(
        f"Automation bridge did not become healthy for {target.device_id} "
        f"at {target.bridge_url}: last_health={last_health}"
    )


def bridge_health_matches_target(
    health: Mapping[str, Any],
    target: MatrixTarget,
) -> bool:
    return (
        health.get("status") == "ok"
        and health.get("automationTargetId") == target.device_id
    )


def wait_for_target_bridge(target: MatrixTarget, deadline: float) -> None:
    last_health: dict[str, Any] = {}
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            last_health = request_json(target.bridge_url, "GET", "/healthz", timeout=3)
            if bridge_health_matches_target(last_health, target):
                return
        except ReproError as error:
            last_error = error
        time.sleep(1)
    raise ReproError(
        f"Automation bridge did not become healthy for {target.device_id} "
        f"at {target.bridge_url}: last_health={last_health}, last_error={last_error}"
    )


def detach_flutter(process: subprocess.Popen[str]) -> None:
    if process.poll() is None and process.stdin is not None:
        process.stdin.write("d\n")
        process.stdin.flush()
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=15)
    log_handle = getattr(process, "_hydracam_log_handle", None)
    if log_handle is not None:
        log_handle.close()


def launch_target(
    target: MatrixTarget,
    rotation_dir: Path,
    *,
    role: str,
    master_ip: str | None,
    timeout: float,
    fast_ios_launch: bool = False,
    xctrace_ios_launch: bool = False,
    xctrace_time_limit_seconds: int = 3600,
) -> subprocess.Popen[str] | None:
    if target.platform == "android":
        launch_android_target(target, role=role, master_ip=master_ip)
        wait_for_target_bridge(target, time.time() + timeout)
        return None
    if target.platform == "ios_physical" and fast_ios_launch:
        try:
            launch_ios_fast_target(
                target,
                rotation_dir,
                role=role,
                master_ip=master_ip,
                timeout=timeout,
            )
            return None
        except Exception as error:
            if not xctrace_ios_launch:
                raise
            target_dir = rotation_dir / target.slug
            target_dir.mkdir(parents=True, exist_ok=True)
            (target_dir / "fast-ios-launch-fallback.txt").write_text(
                str(error) + "\n",
                encoding="utf-8",
            )
    if target.platform == "ios_physical" and xctrace_ios_launch:
        return launch_ios_xctrace_target(
            target,
            rotation_dir,
            role=role,
            master_ip=master_ip,
            timeout=timeout,
            time_limit_seconds=xctrace_time_limit_seconds,
        )
    if target.platform == "macos" and role == "standby":
        return launch_macos_standby_target(
            target,
            rotation_dir,
            timeout=timeout,
        )
    if target.platform in {"ios_physical", "ios_simulator", "macos"}:
        return launch_flutter_target(
            target,
            rotation_dir,
            role=role,
            master_ip=master_ip,
            timeout=timeout,
        )
    raise MatrixConfigError(f"Unsupported target platform: {target.platform}")


def wait_connected_clients(
    master: MatrixTarget,
    *,
    expected_count: int,
    timeout: float,
    poll_interval: float = DEFAULT_CONNECTED_CLIENT_POLL_INTERVAL_SECONDS,
) -> dict[str, Any]:
    deadline = time.time() + timeout
    last_payload: dict[str, Any] = {}
    while time.time() < deadline:
        response = post_command(master.bridge_url, "connected_clients", {}, deadline)
        result = response.get("result")
        if isinstance(result, dict):
            last_payload = result
            if int(result.get("connectedClientCount", 0)) >= expected_count:
                return result
        time.sleep(poll_interval)
    raise ReproError(
        "Timed out waiting for connected slave clients on "
        f"{master.device_id}: expected {expected_count}, last={last_payload}"
    )


def _connected_client_remote_ips(payload: Mapping[str, Any]) -> set[str]:
    clients = payload.get("connectedClients", [])
    if not isinstance(clients, list):
        return set()
    remote_ips: set[str] = set()
    for client in clients:
        if not isinstance(client, Mapping):
            continue
        remote_ip = client.get("remoteIp")
        if isinstance(remote_ip, str) and remote_ip:
            remote_ips.add(remote_ip)
    return remote_ips


def expected_client_remote_ips(
    rotation: MatrixRotation,
    master_hosts: Mapping[str, str],
) -> set[str]:
    remote_ips: set[str] = set()
    for client in rotation.clients:
        remote_ips.add(master_hosts.get(client.device_id, client.host))
    return remote_ips


def wait_expected_connected_clients(
    rotation: MatrixRotation,
    *,
    master_hosts: Mapping[str, str],
    timeout: float,
    poll_interval: float = DEFAULT_CONNECTED_CLIENT_POLL_INTERVAL_SECONDS,
) -> dict[str, Any]:
    expected_remote_ips = expected_client_remote_ips(rotation, master_hosts)
    deadline = time.time() + timeout
    last_payload: dict[str, Any] = {}
    last_remote_ips: set[str] = set()
    while time.time() < deadline:
        response = post_command(
            rotation.master.bridge_url,
            "connected_clients",
            {},
            deadline,
        )
        result = response.get("result")
        if isinstance(result, dict):
            last_payload = result
            last_remote_ips = _connected_client_remote_ips(result)
            if expected_remote_ips.issubset(last_remote_ips):
                return result
        time.sleep(poll_interval)
    raise ReproError(
        "Timed out waiting for expected connected slave client remote IPs on "
        f"{rotation.master.device_id}: expected={sorted(expected_remote_ips)}, "
        f"seen={sorted(last_remote_ips)}, last={last_payload}"
    )


def apply_runtime_role_switch(
    rotation: MatrixRotation,
    *,
    targets: Sequence[MatrixTarget],
    master_host: str,
    timeout: float,
    stage_slaves_after_master_ready: bool = False,
    master_ready_timeout: float | None = None,
) -> dict[str, Any]:
    payloads = build_runtime_role_payloads(rotation, master_host=master_host)
    targets_by_id = {target.device_id: target for target in targets}
    deadline = time.time() + timeout
    batch_started = time.perf_counter()
    responses: dict[str, Any] = {}
    timings: dict[str, Any] = {}

    def post_role(
        device_id: str,
        payload: dict[str, Any],
        batch: str = "parallel",
    ) -> tuple[str, Any, dict[str, Any]]:
        target = targets_by_id[device_id]
        started_at = dt.datetime.now().isoformat()
        started_offset = time.perf_counter() - batch_started
        response = post_command(target.bridge_url, "set_role", payload, deadline)
        ended_offset = time.perf_counter() - batch_started
        ended_at = dt.datetime.now().isoformat()
        return (
            device_id,
            response,
            {
                "bridgeUrl": target.bridge_url,
                "batch": batch,
                "startedAt": started_at,
                "startOffsetMs": round(started_offset * 1000, 3),
                "endedAt": ended_at,
                "endOffsetMs": round(ended_offset * 1000, 3),
                "durationMs": round((ended_offset - started_offset) * 1000, 3),
            },
        )

    if stage_slaves_after_master_ready:
        master_id = rotation.master.device_id
        device_id, response, timing = post_role(
            master_id,
            payloads[master_id],
            "master",
        )
        responses[device_id] = response
        timings[device_id] = timing
        wait_for_master_commands(
            rotation.master,
            timeout=master_ready_timeout or timeout,
        )

        slave_payloads = {
            device_id: payload
            for device_id, payload in payloads.items()
            if device_id != master_id
        }
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=max(1, len(slave_payloads)),
        ) as executor:
            futures = [
                executor.submit(post_role, device_id, payload, "slaves")
                for device_id, payload in slave_payloads.items()
            ]
            for future in concurrent.futures.as_completed(futures):
                device_id, response, timing = future.result()
                responses[device_id] = response
                timings[device_id] = timing
        return RuntimeRoleSwitchResponses(
            responses,
            timings=timings,
            mode="master_ready_then_parallel_slaves",
        )

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=max(1, len(payloads)),
    ) as executor:
        futures = [
            executor.submit(post_role, device_id, payload)
            for device_id, payload in payloads.items()
        ]
        for future in concurrent.futures.as_completed(futures):
            device_id, response, timing = future.result()
            responses[device_id] = response
            timings[device_id] = timing
    return RuntimeRoleSwitchResponses(responses, timings=timings)


def _timing_skew_ms(timings: Mapping[str, Any], key: str) -> float | None:
    values = [
        timing.get(key)
        for timing in timings.values()
        if isinstance(timing, Mapping) and isinstance(timing.get(key), (int, float))
    ]
    if not values:
        return None
    return round(max(values) - min(values), 3)


def _filtered_timing_skew_ms(
    timings: Mapping[str, Any],
    key: str,
    *,
    batch: str,
) -> float | None:
    filtered = {
        device_id: timing
        for device_id, timing in timings.items()
        if isinstance(timing, Mapping) and timing.get("batch") == batch
    }
    return _timing_skew_ms(filtered, key)


def _max_timing_ms(timings: Mapping[str, Any], key: str) -> float | None:
    values = [
        timing.get(key)
        for timing in timings.values()
        if isinstance(timing, Mapping) and isinstance(timing.get(key), (int, float))
    ]
    if not values:
        return None
    return round(max(values), 3)


def build_runtime_role_switch_snapshot(
    responses: Mapping[str, Any],
    *,
    started_at: str,
    elapsed_seconds: float,
) -> dict[str, Any]:
    snapshot = {
        "startedAt": started_at,
        "elapsedMs": round(elapsed_seconds * 1000, 3),
        "responses": responses,
    }
    timings = getattr(responses, "timings", None)
    if isinstance(timings, Mapping) and timings:
        mode = getattr(responses, "mode", "parallel")
        snapshot["mode"] = mode
        snapshot["requestTimings"] = timings
        snapshot["requestStartSkewMs"] = _timing_skew_ms(timings, "startOffsetMs")
        snapshot["requestEndSkewMs"] = _timing_skew_ms(timings, "endOffsetMs")
        snapshot["maxRequestDurationMs"] = _max_timing_ms(timings, "durationMs")
        slave_start_skew = _filtered_timing_skew_ms(
            timings,
            "startOffsetMs",
            batch="slaves",
        )
        if slave_start_skew is not None:
            snapshot["parallelRequestStartSkewMs"] = slave_start_skew
        else:
            snapshot["parallelRequestStartSkewMs"] = snapshot[
                "requestStartSkewMs"
            ]
    return snapshot


def wait_for_master_commands(
    master: MatrixTarget,
    *,
    timeout: float,
    poll_interval: float = DEFAULT_CONNECTED_CLIENT_POLL_INTERVAL_SECONDS,
) -> None:
    deadline = time.time() + timeout
    last_health: dict[str, Any] = {}
    while time.time() < deadline:
        try:
            last_health = request_json(master.bridge_url, "GET", "/healthz", timeout=5)
            commands = last_health.get("commands", [])
            if isinstance(commands, list) and "connected_clients" in commands:
                return
        except ReproError:
            pass
        time.sleep(poll_interval)
    raise ReproError(
        f"Timed out waiting for {master.device_id} to expose master commands: "
        f"{last_health}"
    )


def bridge_supports_runtime_role_switch(target: MatrixTarget) -> bool:
    try:
        health = request_json(target.bridge_url, "GET", "/healthz", timeout=3)
    except ReproError:
        return False
    commands = health.get("commands", [])
    if health.get("automationTargetId") != target.device_id:
        return False
    return health.get("status") == "ok" and isinstance(commands, list) and (
        "set_role" in commands
    )


def missing_warm_runtime_bridges(targets: Sequence[MatrixTarget]) -> list[dict[str, str]]:
    return [
        {
            "deviceId": target.device_id,
            "bridgeUrl": target.bridge_url,
            "platform": target.platform,
        }
        for target in targets
        if not bridge_supports_runtime_role_switch(target)
    ]


def require_warm_runtime_bridges(targets: Sequence[MatrixTarget]) -> None:
    missing = missing_warm_runtime_bridges(targets)
    if missing:
        joined = ", ".join(
            f"{entry['deviceId']} ({entry['bridgeUrl']})"
            for entry in missing
        )
        raise MatrixRunError(f"Required warm runtime bridge missing: {joined}")


def _warm_prime_device_action(
    entry: Mapping[str, Any],
    target: MatrixTarget | None,
    launch_error: str,
) -> dict[str, str]:
    device_id = str(entry["deviceId"])
    platform = str(entry["platform"])
    bridge_url = str(entry["bridgeUrl"])
    lowered = launch_error.lower()
    if platform == "ios_physical" and "ios_profile_not_trusted" in lowered:
        return {
            "deviceId": device_id,
            "platform": platform,
            "bridgeUrl": bridge_url,
            "code": "ios_profile_not_trusted",
            "action": (
                "On the iOS device, open Settings > General > VPN & Device "
                "Management and trust the developer profile for the installed "
                "HydraCam build. Keep the device unlocked, then rerun "
                "--prime-then-immediate-role-switch --xctrace-ios-launch."
            ),
        }
    if platform == "ios_physical" and (
        "code -27" in lowered
        or "device is locked" in lowered
        or "device be unlocked" in lowered
    ):
        return {
            "deviceId": device_id,
            "platform": platform,
            "bridgeUrl": bridge_url,
            "code": "ios_device_unreachable",
            "action": (
                "Unlock the iOS device, connect it by cable or restore wireless "
                "debugging, confirm Developer Mode is enabled, then rerun "
                "--prime-then-immediate-role-switch."
            ),
        }
    if platform == "ios_physical" and (
        "automation bridge did not become healthy" in lowered
        or "connection refused" in lowered
    ):
        return {
            "deviceId": device_id,
            "platform": platform,
            "bridgeUrl": bridge_url,
            "code": "ios_launch_no_bridge",
            "action": (
                "The iOS app launch path ran, but the automation bridge never "
                "appeared at the expected host. Keep the device unlocked and "
                "foregrounded, confirm it is on the same Wi-Fi, and reinstall "
                "or relaunch a current automation-enabled HydraCam build before "
                "rerunning the warm-prime matrix."
            ),
        }
    if platform == "ios_physical":
        return {
            "deviceId": device_id,
            "platform": platform,
            "bridgeUrl": bridge_url,
            "code": "ios_warm_bridge_missing",
            "action": (
                "Launch the installed automation-enabled HydraCam build on the "
                "iOS device, or rerun with --xctrace-ios-launch if the device "
                "is visible through xcdevice."
            ),
        }
    if platform == "android":
        return {
            "deviceId": device_id,
            "platform": platform,
            "bridgeUrl": bridge_url,
            "code": "android_warm_bridge_missing",
            "action": (
                "Confirm the Android device is connected over ADB and has the "
                "current automation-enabled HydraCam APK installed, then rerun "
                "--prime-then-immediate-role-switch."
            ),
        }
    label = target.label if target is not None else device_id
    return {
        "deviceId": device_id,
        "platform": platform,
        "bridgeUrl": bridge_url,
        "code": "warm_bridge_missing",
        "action": (
            f"Warm the automation bridge for {label} at {bridge_url}, then "
            "rerun --prime-then-immediate-role-switch."
        ),
    }


def warm_prime_device_actions(
    missing: Sequence[Mapping[str, Any]],
    targets: Sequence[MatrixTarget],
    *,
    launch_error: str,
) -> list[dict[str, str]]:
    targets_by_id = {target.device_id: target for target in targets}
    return [
        _warm_prime_device_action(
            entry,
            targets_by_id.get(str(entry["deviceId"])),
            launch_error,
        )
        for entry in missing
    ]


def ios_profile_trust_retry_needed(
    missing: Sequence[Mapping[str, Any]],
    launch_error: str,
) -> bool:
    return (
        "ios_profile_not_trusted" in launch_error.lower()
        and any(str(entry.get("platform")) == "ios_physical" for entry in missing)
    )


def _missing_warm_bridge_device_ids(
    missing: Sequence[Mapping[str, Any]],
) -> list[str]:
    return [str(entry["deviceId"]) for entry in missing]


def warm_prime_runtime_bridges(
    targets: Sequence[MatrixTarget],
    run_dir: Path,
    *,
    timeout: float,
    apk: Path,
    master_hosts: Mapping[str, str] | None = None,
    fast_ios_launch: bool,
    xctrace_ios_launch: bool,
    xctrace_time_limit_seconds: int,
    ios_profile_trust_retry_timeout: float = 0,
    ios_profile_trust_retry_interval: float = 5,
) -> int:
    before_missing = missing_warm_runtime_bridges(targets)
    summary: dict[str, Any] = {
        "status": "passed" if not before_missing else "started",
        "targetCount": len(targets),
        "targets": [target_to_json(target) for target in targets],
        "masterHosts": dict(master_hosts or {}),
        "initialMissingWarmBridgeDeviceIds": _missing_warm_bridge_device_ids(
            before_missing,
        ),
        "initialMissingWarmBridges": before_missing,
        "launchAttempted": bool(before_missing),
    }
    if before_missing:
        missing_ids = {
            entry["deviceId"]
            for entry in before_missing
        }
        for target in targets:
            if target.platform == "android" and target.device_id in missing_ids:
                prepare_android_target(
                    target,
                    apk,
                    skip_install=True,
                    reuse_running_bridge=True,
                )
        try:
            launch_standby_targets(
                targets,
                run_dir / "warm-prime-launch",
                timeout=timeout,
                fast_ios_launch=fast_ios_launch,
                xctrace_ios_launch=xctrace_ios_launch,
                xctrace_time_limit_seconds=xctrace_time_limit_seconds,
                reuse_running_bridges=True,
            )
        except Exception as error:
            summary["launchError"] = str(error)
    after_missing = missing_warm_runtime_bridges(targets)
    retry_timeout = max(0.0, float(ios_profile_trust_retry_timeout or 0))
    if (
        after_missing
        and retry_timeout > 0
        and ios_profile_trust_retry_needed(
            after_missing,
            str(summary.get("launchError") or ""),
        )
    ):
        attempts: list[dict[str, Any]] = []
        summary["iosProfileTrustRetryStartedAt"] = dt.datetime.now().isoformat()
        deadline = time.time() + retry_timeout
        retry_interval = max(0.0, float(ios_profile_trust_retry_interval or 0))
        attempt_index = 0
        while after_missing and time.time() < deadline:
            if retry_interval > 0:
                sleep_seconds = min(retry_interval, max(0.0, deadline - time.time()))
                if sleep_seconds > 0:
                    time.sleep(sleep_seconds)
            if time.time() >= deadline:
                break
            attempt_index += 1
            attempt: dict[str, Any] = {
                "attempt": attempt_index,
                "startedAt": dt.datetime.now().isoformat(),
                "missingBeforeAttemptDeviceIds": _missing_warm_bridge_device_ids(
                    after_missing,
                ),
            }
            try:
                launch_standby_targets(
                    targets,
                    run_dir / f"warm-prime-launch-trust-retry-{attempt_index:02d}",
                    timeout=timeout,
                    fast_ios_launch=fast_ios_launch,
                    xctrace_ios_launch=xctrace_ios_launch,
                    xctrace_time_limit_seconds=xctrace_time_limit_seconds,
                    reuse_running_bridges=True,
                )
            except Exception as error:
                attempt["launchError"] = str(error)
                summary["launchError"] = str(error)
            after_missing = missing_warm_runtime_bridges(targets)
            attempt["missingAfterAttemptDeviceIds"] = _missing_warm_bridge_device_ids(
                after_missing,
            )
            attempts.append(attempt)
            if after_missing and not ios_profile_trust_retry_needed(
                after_missing,
                str(summary.get("launchError") or ""),
            ):
                break
        summary["iosProfileTrustRetryAttempts"] = attempts
        summary["iosProfileTrustRetryEndedAt"] = dt.datetime.now().isoformat()
    summary["finalMissingWarmBridgeDeviceIds"] = _missing_warm_bridge_device_ids(
        after_missing,
    )
    summary["finalMissingWarmBridges"] = after_missing
    summary["status"] = "failed" if after_missing else "passed"
    if after_missing:
        summary["deviceActions"] = warm_prime_device_actions(
            after_missing,
            targets,
            launch_error=str(summary.get("launchError") or ""),
        )
    write_json(run_dir / "warm-bridge-prime.json", summary)
    return 1 if after_missing else 0


def launch_standby_targets(
    targets: Sequence[MatrixTarget],
    run_dir: Path,
    *,
    timeout: float,
    fast_ios_launch: bool,
    xctrace_ios_launch: bool = False,
    xctrace_time_limit_seconds: int = 28800,
    reuse_running_bridges: bool = False,
) -> dict[str, subprocess.Popen[str]]:
    processes: dict[str, subprocess.Popen[str]] = {}
    targets_to_launch = [
        target
        for target in targets
        if not (
            reuse_running_bridges and bridge_supports_runtime_role_switch(target)
        )
    ]
    android_targets = [
        target for target in targets_to_launch if target.platform == "android"
    ]
    flutter_targets = [
        target
        for target in targets_to_launch
        if target.platform in {"ios_physical", "ios_simulator", "macos"}
    ]

    def launch_android_standby(target: MatrixTarget) -> None:
        launch_target(
            target,
            run_dir,
            role="standby",
            master_ip=None,
            timeout=timeout,
            fast_ios_launch=fast_ios_launch,
            xctrace_ios_launch=xctrace_ios_launch,
            xctrace_time_limit_seconds=xctrace_time_limit_seconds,
        )

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(android_targets))) as executor:
        futures = [
            executor.submit(launch_android_standby, target)
            for target in android_targets
        ]
        for future in concurrent.futures.as_completed(futures):
            future.result()

    for target in flutter_targets:
        process = launch_target(
            target,
            run_dir,
            role="standby",
            master_ip=None,
            timeout=timeout,
            fast_ios_launch=fast_ios_launch,
            xctrace_ios_launch=xctrace_ios_launch,
            xctrace_time_limit_seconds=xctrace_time_limit_seconds,
        )
        if process is not None:
            processes[target.device_id] = process

    deadline = time.time() + timeout
    for target in targets:
        wait_for_target_bridge(target, deadline)
    return processes


def _target_requires_media(target: MatrixTarget) -> bool:
    return target.capture_enabled and target.known_blocker is None


def _add_failure(
    states: dict[str, dict[str, Any]],
    target: MatrixTarget,
    stage: str,
    error: object,
) -> None:
    states[target.device_id]["failures"].append(f"{stage}: {error}")


def append_progress_event(
    rotation_dir: Path,
    stage: str,
    status: str,
    details: Mapping[str, Any] | None = None,
) -> None:
    rotation_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "timestamp": dt.datetime.now().isoformat(),
        "stage": stage,
        "status": status,
    }
    if details:
        payload["details"] = dict(details)
    with (rotation_dir / "progress.ndjson").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")


def await_rotation_session_value(
    target: MatrixTarget,
    predicate,
    *,
    timeout: float,
    interval: float = DEFAULT_SESSION_POLL_INTERVAL_SECONDS,
) -> dict[str, Any]:
    deadline = time.time() + timeout
    last_payload: dict[str, Any] = {}
    while time.time() < deadline:
        try:
            last_payload = request_json(
                target.bridge_url,
                "GET",
                "/session",
                timeout=min(2.0, max(0.25, timeout)),
            )
        except Exception as error:
            last_payload = {"error": str(error)}
        if predicate(last_payload):
            return last_payload
        time.sleep(interval)
    raise ReproError(
        f"Timed out waiting for session state on {target.device_id}: {last_payload}"
    )


def wait_for_target_stage(
    targets: Sequence[MatrixTarget],
    states: dict[str, dict[str, Any]],
    stage: str,
    predicate,
    *,
    timeout: float,
    required,
) -> dict[str, Any]:
    snapshots: dict[str, Any] = {}
    required_targets: list[MatrixTarget] = []
    for target in targets:
        if not required(target):
            snapshots[target.device_id] = {"status": "skipped"}
        else:
            required_targets.append(target)

    def wait_one(target: MatrixTarget) -> tuple[MatrixTarget, dict[str, Any], object | None]:
        try:
            snapshot = await_rotation_session_value(
                target,
                predicate,
                timeout=timeout,
            )
            return target, snapshot, None
        except Exception as error:
            return target, {"status": "failed", "error": str(error)}, error

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(required_targets))) as executor:
        futures = [executor.submit(wait_one, target) for target in required_targets]
        for future in concurrent.futures.as_completed(futures):
            target, snapshot, error = future.result()
            if error is not None:
                _add_failure(states, target, stage, error)
            snapshots[target.device_id] = snapshot
    return snapshots


def collect_target_logs(
    rotation_dir: Path,
    targets: Sequence[MatrixTarget],
    states: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    logs: dict[str, Any] = {}
    for target in targets:
        target_dir = rotation_dir / target.slug
        target_dir.mkdir(parents=True, exist_ok=True)
        log_text = ""
        try:
            payload = request_json(target.bridge_url, "GET", "/logs", timeout=15)
            write_json(target_dir / "logs.json", payload)
            logs[target.device_id] = payload
            log_text += json.dumps(payload)
        except Exception as error:
            _add_failure(states, target, "logs", error)
        log_text += "\n" + collect_android_logcat(target, target_dir)
        blocker = classify_known_blocker(target.device_id, log_text)
        if blocker and states[target.device_id].get("knownBlocker") is None:
            states[target.device_id]["knownBlocker"] = blocker
    return logs


def finalize_target_states(states: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for state in states.values():
        failures = state["failures"]
        known_blocker = state.get("knownBlocker")
        capture_enabled = state["target"]["captureEnabled"]
        if not capture_enabled and not failures:
            status = "launch_only"
        elif failures and known_blocker:
            status = "expected_blocker"
        elif failures:
            status = "failed"
        else:
            status = "passed"
        state["status"] = status
        results.append(state)
    return sorted(results, key=lambda result: result["target"]["deviceId"])


def build_rotation_settings_payload(
    target: MatrixTarget,
    master: MatrixTarget,
) -> dict[str, Any]:
    original_master_should_record = None
    if target.device_id == master.device_id and master.device_id == S7_SERIAL:
        original_master_should_record = False
    return {
        "masterShouldRecord": (
            original_master_should_record
            if original_master_should_record is not None
            else True
        ),
        "timerDuration": 0,
        "autoplayVideoOnMaster": False,
        "flashForVideoAnnounce": False,
        "autoUploadMaterials": True,
        "cameraLensPreference": target.lens,
        "videoCaptureProfile": target.profile,
    }


def settings_snapshot_matches_payload(
    snapshot: Mapping[str, Any],
    payload: Mapping[str, Any],
) -> bool:
    for key, expected_value in payload.items():
        if snapshot.get(key) != expected_value:
            return False
    return True


def apply_rotation_settings(target: MatrixTarget, master: MatrixTarget) -> dict[str, Any]:
    payload = build_rotation_settings_payload(target, master)
    try:
        existing = request_json(target.bridge_url, "GET", "/settings", timeout=10)
        if settings_snapshot_matches_payload(existing, payload):
            return {
                **existing,
                "status": "already_applied",
            }
    except Exception:
        pass

    if target.device_id != master.device_id or master.device_id != S7_SERIAL:
        request_json(
            target.bridge_url,
            "POST",
            "/settings",
            payload,
            timeout=20,
        )
        return request_json(target.bridge_url, "GET", "/settings", timeout=20)
    request_json(
        target.bridge_url,
        "POST",
        "/settings",
        payload,
        timeout=20,
    )
    return request_json(target.bridge_url, "GET", "/settings", timeout=20)


def run_rotation_capture_flow(
    rotation: MatrixRotation,
    rotation_dir: Path,
    *,
    record_seconds: float,
    timeout: float,
    master_hosts: Mapping[str, str] | None = None,
    capture_stage_timeout: float = DEFAULT_CAPTURE_STAGE_TIMEOUT_SECONDS,
    recording_ready_timeout: float = DEFAULT_RECORDING_READY_TIMEOUT_SECONDS,
    stop_recording_timeout: float = DEFAULT_STOP_RECORDING_TIMEOUT_SECONDS,
) -> dict[str, Any]:
    targets = [rotation.master, *rotation.clients]
    host_map = master_hosts or {
        target.device_id: target.host
        for target in targets
    }
    states: dict[str, dict[str, Any]] = {
        target.device_id: {
            "target": target_to_json(target),
            "failures": [],
            "knownBlocker": target.known_blocker,
        }
        for target in targets
    }
    snapshots: dict[str, Any] = {}
    command_times: dict[str, str] = {}
    deadline = time.time() + timeout

    try:
        append_progress_event(rotation_dir, "settings", "started")
        settings: dict[str, Any] = {}
        for target in targets:
            settings[target.device_id] = apply_rotation_settings(target, rotation.master)
        snapshots["settings"] = settings
        append_progress_event(
            rotation_dir,
            "settings",
            "completed",
            {"targetCount": len(settings)},
        )

        append_progress_event(rotation_dir, "connected_clients", "started")
        snapshots["connected_clients"] = wait_expected_connected_clients(
            rotation,
            master_hosts=host_map,
            timeout=min(DEFAULT_CONNECTION_TIMEOUT_SECONDS, timeout),
        )
        append_progress_event(rotation_dir, "connected_clients", "completed")

        session_id = f"rotation-{rotation.master.device_id}-{int(time.time())}"
        append_progress_event(rotation_dir, "start_session", "started")
        command_times["start_session"] = dt.datetime.now().isoformat()
        snapshots["start_session"] = post_command(
            rotation.master.bridge_url,
            "start_session",
            {"sessionId": session_id},
            deadline,
        )
        snapshots["after_start_session"] = wait_for_target_stage(
            targets,
            states,
            "start_session",
            lambda payload: payload.get("isActive") is True,
            timeout=min(capture_stage_timeout, timeout),
            required=lambda target: True,
        )
        append_progress_event(rotation_dir, "start_session", "completed")

        append_progress_event(rotation_dir, "take_photo", "started")
        command_times["take_photo"] = dt.datetime.now().isoformat()
        snapshots["take_photo"] = post_command(
            rotation.master.bridge_url,
            "take_photo",
            {"showCountdown": False},
            deadline,
        )
        snapshots["after_take_photo"] = wait_for_target_stage(
            targets,
            states,
            "take_photo",
            lambda payload: int(payload.get("photoCount", 0)) >= 1,
            timeout=min(capture_stage_timeout, timeout),
            required=_target_requires_media,
        )
        append_progress_event(rotation_dir, "take_photo", "completed")

        append_progress_event(rotation_dir, "start_recording", "started")
        command_times["start_recording"] = dt.datetime.now().isoformat()
        snapshots["start_recording"] = post_command(
            rotation.master.bridge_url,
            "start_recording",
            {},
            deadline,
        )
        snapshots["after_start_recording"] = wait_for_target_stage(
            targets,
            states,
            "start_recording",
            lambda payload: payload.get("isRecording") is True,
            timeout=min(recording_ready_timeout, timeout),
            required=_target_requires_media,
        )
        append_progress_event(rotation_dir, "start_recording", "completed")

        time.sleep(record_seconds)
        append_progress_event(rotation_dir, "stop_recording", "started")
        command_times["stop_recording"] = dt.datetime.now().isoformat()
        snapshots["stop_recording"] = post_command(
            rotation.master.bridge_url,
            "stop_recording",
            {},
            deadline,
        )
        snapshots["after_stop_recording"] = wait_for_target_stage(
            targets,
            states,
            "stop_recording",
            lambda payload: int(payload.get("videoCount", 0)) >= 1
            and payload.get("isRecording") is False,
            timeout=min(stop_recording_timeout, timeout),
            required=_target_requires_media,
        )
        append_progress_event(rotation_dir, "stop_recording", "completed")

        append_progress_event(rotation_dir, "end_session", "started")
        command_times["end_session"] = dt.datetime.now().isoformat()
        snapshots["end_session"] = post_command(
            rotation.master.bridge_url,
            "end_session",
            {},
            deadline,
        )
        snapshots["after_end_session"] = wait_for_target_stage(
            targets,
            states,
            "end_session",
            lambda payload: payload.get("isActive") is False,
            timeout=min(capture_stage_timeout, timeout),
            required=lambda target: True,
        )
        append_progress_event(rotation_dir, "end_session", "completed")
    except Exception as error:
        _add_failure(states, rotation.master, "rotation", error)
        snapshots["rotation_error"] = str(error)
        append_progress_event(
            rotation_dir,
            "rotation",
            "failed",
            {"error": str(error)},
        )
    finally:
        append_progress_event(rotation_dir, "logs", "started")
        snapshots["logs"] = collect_target_logs(rotation_dir, targets, states)
        append_progress_event(rotation_dir, "logs", "completed")

    target_results = finalize_target_states(states)
    status = "passed"
    if any(result["status"] == "failed" for result in target_results):
        status = "failed"
    elif any(result["status"] == "expected_blocker" for result in target_results):
        status = "completed_with_known_blockers"
    rotation_result = {
        **rotation_to_json(rotation),
        "status": status,
        "barrierReleasedAt": command_times.get("start_session"),
        "commandTimes": command_times,
        "targetResults": target_results,
        "failures": [
            failure
            for result in target_results
            for failure in result.get("failures", [])
            if result.get("status") == "failed"
        ],
    }
    write_json(rotation_dir / "automation-snapshots.json", snapshots)
    write_json(rotation_dir / "summary.json", rotation_result)
    return rotation_result


def run_role_switch_only_flow(
    rotation: MatrixRotation,
    rotation_dir: Path,
    *,
    timeout: float,
    master_hosts: Mapping[str, str] | None = None,
    collect_logs: bool = False,
    phase_timings: MutableMapping[str, Any] | None = None,
) -> dict[str, Any]:
    targets = [rotation.master, *rotation.clients]
    host_map = master_hosts or {
        target.device_id: target.host
        for target in targets
    }
    states: dict[str, dict[str, Any]] = {
        target.device_id: {
            "target": target_to_json(target),
            "failures": [],
            "knownBlocker": target.known_blocker,
        }
        for target in targets
    }
    snapshots: dict[str, Any] = {}
    timings = phase_timings if phase_timings is not None else {}

    try:
        snapshots["connected_clients"] = timed_phase(
            timings,
            "connected_clients",
            lambda: wait_expected_connected_clients(
                rotation,
                master_hosts=host_map,
                timeout=timeout,
            ),
        )
    except Exception as error:
        _add_failure(states, rotation.master, "role_switch", error)
        snapshots["role_switch_error"] = str(error)
    finally:
        has_failures = any(state["failures"] for state in states.values())
        if collect_logs or has_failures:
            snapshots["logs"] = collect_target_logs(rotation_dir, targets, states)
        else:
            snapshots["logs"] = {"status": "skipped_on_success"}
        snapshots["phaseTimings"] = dict(timings)

    target_results: list[dict[str, Any]] = []
    for state in states.values():
        failures = state["failures"]
        known_blocker = state.get("knownBlocker")
        if failures and known_blocker:
            status = "expected_blocker"
        elif failures:
            status = "failed"
        else:
            status = "role_switched"
        state["status"] = status
        target_results.append(state)
    target_results = sorted(
        target_results,
        key=lambda result: result["target"]["deviceId"],
    )

    status = "passed"
    if any(result["status"] == "failed" for result in target_results):
        status = "failed"
    elif any(result["status"] == "expected_blocker" for result in target_results):
        status = "completed_with_known_blockers"
    rotation_result = {
        **rotation_to_json(rotation),
        "status": status,
        "roleSwitchOnly": True,
        "connectedClientsSnapshot": snapshots.get("connected_clients"),
        "targetResults": target_results,
        "failures": [
            failure
            for result in target_results
            for failure in result.get("failures", [])
            if result.get("status") == "failed"
        ],
        "phaseTimings": dict(timings),
    }
    write_json(rotation_dir / "automation-snapshots.json", snapshots)
    write_json(rotation_dir / "summary.json", rotation_result)
    return rotation_result


def launch_rotation(
    rotation: MatrixRotation,
    targets: Sequence[MatrixTarget],
    master_hosts: Mapping[str, str],
    rotation_dir: Path,
    *,
    timeout: float,
    fast_ios_launch: bool,
) -> dict[str, subprocess.Popen[str]]:
    processes: dict[str, subprocess.Popen[str]] = {}
    master_host = master_hosts.get(rotation.master.device_id)
    if not master_host:
        raise MatrixRunError(f"No master host resolved for {rotation.master.device_id}")

    master_process = launch_target(
        rotation.master,
        rotation_dir,
        role="master",
        master_ip=None,
        timeout=timeout,
        fast_ios_launch=fast_ios_launch,
    )
    if master_process is not None:
        processes[rotation.master.device_id] = master_process

    android_clients = [
        client for client in rotation.clients if client.platform == "android"
    ]
    flutter_clients = [
        client
        for client in rotation.clients
        if client.platform in {"ios_physical", "ios_simulator", "macos"}
    ]

    def launch_android_client(client: MatrixTarget) -> None:
        launch_target(
            client,
            rotation_dir,
            role="slave",
            master_ip=master_host,
            timeout=timeout,
            fast_ios_launch=fast_ios_launch,
        )

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(android_clients))) as executor:
        futures = [
            executor.submit(launch_android_client, client)
            for client in android_clients
        ]
        for future in concurrent.futures.as_completed(futures):
            future.result()

    def launch_flutter_client(client: MatrixTarget) -> tuple[str, subprocess.Popen[str] | None]:
        process = launch_target(
            client,
            rotation_dir,
            role="slave",
            master_ip=master_host,
            timeout=timeout,
            fast_ios_launch=fast_ios_launch,
        )
        return client.device_id, process

    for client in flutter_clients:
        device_id, process = launch_flutter_client(client)
        if process is not None:
            processes[device_id] = process

    deadline = time.time() + timeout
    for target in targets:
        wait_for_target_bridge(target, deadline)
    return processes


def stop_processes(processes: Mapping[str, subprocess.Popen[str]]) -> None:
    for process in processes.values():
        stop_flutter(process)


def build_ios_process_list_command(
    target: MatrixTarget,
    json_output: Path,
) -> list[str]:
    return [
        "xcrun",
        "devicectl",
        "device",
        "info",
        "processes",
        "--device",
        target.device_id,
        "--json-output",
        str(json_output),
        "--quiet",
    ]


def parse_devicectl_process_ids(payload: Mapping[str, Any]) -> list[int]:
    result = payload.get("result", {})
    if not isinstance(result, Mapping):
        return []
    processes = result.get("runningProcesses", [])
    if not isinstance(processes, list):
        return []
    process_ids: list[int] = []
    for process in processes:
        if not isinstance(process, Mapping):
            continue
        executable = process.get("executable")
        if isinstance(executable, Mapping):
            executable_path = str(
                executable.get("path")
                or executable.get("absoluteString")
                or executable.get("url")
                or ""
            )
        else:
            executable_path = str(executable or "")
        if (
            "Runner.app/Runner" not in executable_path
            and "HydraCam.app/HydraCam" not in executable_path
        ):
            continue
        value = process.get("processIdentifier", process.get("pid"))
        if isinstance(value, int):
            process_ids.append(value)
    return process_ids


def build_ios_profile_app() -> None:
    run_command(
        [
            "flutter",
            "build",
            "ios",
            "--profile",
            "--dart-define=HYDRACAM_AUTOMATION=true",
            f"--dart-define=HYDRACAM_AUTOMATION_PORT={DEFAULT_PORT}",
            "-t",
            "lib/main.dart",
        ],
        timeout=1800,
    )


def resolve_ios_profile_app_path(app_path: Path) -> Path:
    if app_path.exists():
        return app_path
    if app_path == IOS_PROFILE_APP:
        for candidate in IOS_PROFILE_APP_FALLBACKS:
            if candidate.exists():
                return candidate
    return app_path


def build_devicectl_ios_profile_install_command(
    target: MatrixTarget,
    app_path: Path,
    json_output_path: Path,
) -> list[str]:
    return [
        "xcrun",
        "devicectl",
        "device",
        "install",
        "app",
        "--device",
        target.device_id,
        str(app_path),
        "--json-output",
        str(json_output_path),
    ]


def package_ios_profile_ipa(app_path: Path, ipa_path: Path) -> Path:
    if app_path.is_file():
        return app_path
    if not app_path.is_dir():
        raise MatrixRunError(f"iOS profile app is not a directory: {app_path}")
    if ipa_path.exists():
        ipa_path.unlink()
    ipa_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="hydracam-ios-profile-ipa-") as tmp:
        tmp_path = Path(tmp)
        payload_dir = tmp_path / "Payload"
        payload_dir.mkdir()
        shutil.copytree(app_path, payload_dir / app_path.name, symlinks=True)
        with zipfile.ZipFile(ipa_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(payload_dir.rglob("*")):
                archive.write(path, path.relative_to(tmp_path))
    return ipa_path


def build_flutter_ios_profile_install_command(
    target: MatrixTarget,
    ipa_path: Path,
) -> list[str]:
    return [
        "flutter",
        "install",
        "-d",
        target.device_id,
        "--use-application-binary",
        str(ipa_path),
    ]


def run_command_with_output_artifacts(
    command: Sequence[str],
    *,
    stdout_path: Path,
    stderr_path: Path,
    timeout: float,
) -> subprocess.CompletedProcess[str]:
    try:
        result = run_command(
            command,
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.CalledProcessError as error:
        stdout_path.write_text(error.stdout or "", encoding="utf-8")
        stderr_path.write_text(error.stderr or "", encoding="utf-8")
        raise
    stdout_path.write_text(result.stdout or "", encoding="utf-8")
    stderr_path.write_text(result.stderr or "", encoding="utf-8")
    return result


def install_ios_profile_app(
    target: MatrixTarget,
    app_path: Path,
    run_dir: Path,
) -> None:
    app_path = resolve_ios_profile_app_path(app_path)
    if not app_path.exists():
        candidates = ", ".join(str(path) for path in IOS_PROFILE_APP_FALLBACKS)
        raise MatrixRunError(
            f"iOS profile app not found: {app_path}. Checked fallbacks: {candidates}"
        )
    target_dir = run_dir / "ios-profile-install" / target.slug
    target_dir.mkdir(parents=True, exist_ok=True)
    try:
        run_command_with_output_artifacts(
            build_devicectl_ios_profile_install_command(
                target,
                app_path,
                target_dir / "devicectl-install.json",
            ),
            stdout_path=target_dir / "devicectl-install.stdout.txt",
            stderr_path=target_dir / "devicectl-install.stderr.txt",
            timeout=600,
        )
        return
    except subprocess.CalledProcessError as error:
        (target_dir / "devicectl-install-fallback.txt").write_text(
            f"devicectl install failed with exit code {error.returncode}; "
            "falling back to flutter install --use-application-binary.\n",
            encoding="utf-8",
        )
    ipa_path = package_ios_profile_ipa(
        app_path,
        target_dir / "hydracam-profile.ipa",
    )
    run_command_with_output_artifacts(
        build_flutter_ios_profile_install_command(target, ipa_path),
        stdout_path=target_dir / "flutter-install.stdout.txt",
        stderr_path=target_dir / "flutter-install.stderr.txt",
        timeout=900,
    )


def build_flutter_app_terminate_command(target: MatrixTarget) -> list[str] | None:
    if target.platform == "ios_simulator":
        return ["xcrun", "simctl", "terminate", target.device_id, IOS_BUNDLE_ID]
    if target.platform == "macos":
        return ["pkill", "-x", "HydraCam"]
    return None


def terminate_ios_physical_app(target: MatrixTarget) -> None:
    with tempfile.NamedTemporaryFile(
        prefix="hydracam-devicectl-processes-",
        suffix=".json",
        delete=False,
    ) as handle:
        json_path = Path(handle.name)
    try:
        run_command(
            build_ios_process_list_command(target, json_path),
            check=False,
            capture_output=True,
            timeout=20,
        )
        try:
            payload = json.loads(json_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            payload = {}
        for process_id in parse_devicectl_process_ids(payload):
            run_command(
                [
                    "xcrun",
                    "devicectl",
                    "device",
                    "process",
                    "terminate",
                    "--device",
                    target.device_id,
                    "--pid",
                    str(process_id),
                    "--quiet",
                ],
                check=False,
                capture_output=True,
                timeout=20,
            )
    finally:
        try:
            json_path.unlink()
        except OSError:
            pass


def terminate_flutter_app_target(target: MatrixTarget) -> None:
    if target.platform == "ios_physical":
        terminate_ios_physical_app(target)
        return
    command = build_flutter_app_terminate_command(target)
    if command is not None:
        run_command(command, check=False, capture_output=True, timeout=20)


def terminate_flutter_app_targets(targets: Sequence[MatrixTarget]) -> None:
    for target in targets:
        if target.platform in {"ios_physical", "ios_simulator", "macos"}:
            terminate_flutter_app_target(target)


def run_matrix(args: argparse.Namespace) -> int:
    apply_immediate_role_switch_defaults(args)
    apply_warm_prime_defaults(args)
    warm_master_hosts: dict[str, str] | None = None
    run_dir = args.run_dir or REPO_ROOT / "logs" / "verification-runs" / now_slug()
    run_dir.mkdir(parents=True, exist_ok=True)
    warm_summary_path = resolve_warm_summary_path(args, run_dir)
    if (
        warm_summary_path is not None
        and getattr(args, "_hydracam_used_latest_warm_summary", False)
        and getattr(args, "_hydracam_auto_ios_bridge_hosts", False)
    ):
        args.auto_ios_bridge_hosts = False
    if warm_summary_path is not None:
        warm_targets, warm_master_hosts = load_warm_summary_targets(warm_summary_path)
        targets = filter_targets_by_device_ids(warm_targets, args.target_id)
    else:
        prefill_ios_hosts_from_running_bridges(args, run_dir)
        targets = filter_targets_by_device_ids(discover_targets(args), args.target_id)
    targets = normalize_direct_macos_bridge_ports(targets)
    if args.reuse_running_bridges:
        targets = adopt_running_bridge_ports(
            targets,
            android_port_base=args.android_port_base,
            local_port_base=args.local_port_base,
        )
    targets, ios_host_matches = adopt_running_ios_bridge_hosts(targets, args, run_dir)
    if warm_master_hosts is not None and ios_host_matches:
        warm_master_hosts = {
            **warm_master_hosts,
            **{
                device_id: str(match["host"])
                for device_id, match in ios_host_matches.items()
            },
        }
    rotations = filter_rotations_by_master_ids(
        build_rotations(targets),
        args.master_id,
    )
    enforce_expected_targets(
        targets,
        getattr(args, "expect_target_id", []),
        run_dir,
    )
    repeat_role_switch_cycles = max(
        1,
        int(getattr(args, "repeat_role_switch_cycles", 1) or 1),
    )
    if repeat_role_switch_cycles > 1 and not (
        args.runtime_role_switch and args.role_switch_only
    ):
        raise MatrixConfigError(
            "--repeat-role-switch-cycles requires runtime role-switch "
            "role-switch-only mode"
        )
    max_set_role_request_start_skew_ms = getattr(
        args,
        "max_set_role_request_start_skew_ms",
        None,
    )

    if args.dry_run:
        summary = build_dry_run_summary(
            targets,
            rotations,
            runtime_role_switch=args.runtime_role_switch,
            role_switch_only=args.role_switch_only,
            repeat_role_switch_cycles=repeat_role_switch_cycles,
        )
        write_json(run_dir / "summary.json", summary)
        write_summary_markdown(run_dir, summary)
        print(json.dumps(summary, indent=2, sort_keys=True))
        return 0

    ios_physical_targets = [
        target for target in targets if target.platform == "ios_physical"
    ]
    if ios_physical_targets and should_build_ios_profile_app(args):
        build_ios_profile_app()
    if ios_physical_targets and should_install_ios_profile_app(args):
        for target in ios_physical_targets:
            install_ios_profile_app(target, args.ios_profile_app, run_dir)

    if getattr(args, "warm_prime_only", False):
        exit_code = warm_prime_runtime_bridges(
            targets,
            run_dir,
            timeout=(
                getattr(args, "standby_launch_timeout", None)
                or args.timeout
            ),
            apk=args.apk,
            master_hosts=warm_master_hosts,
            fast_ios_launch=args.fast_ios_launch,
            xctrace_ios_launch=getattr(args, "xctrace_ios_launch", False),
            xctrace_time_limit_seconds=getattr(
                args,
                "xctrace_time_limit_seconds",
                28800,
            ),
            ios_profile_trust_retry_timeout=getattr(
                args,
                "ios_profile_trust_retry_timeout",
                0,
            ),
            ios_profile_trust_retry_interval=getattr(
                args,
                "ios_profile_trust_retry_interval",
                5,
            ),
        )
        if exit_code == 0:
            write_latest_warm_summary_cache(
                args,
                run_dir,
                targets=targets,
                master_hosts=warm_master_hosts,
                source_artifact=run_dir / "warm-bridge-prime.json",
            )
        print(run_dir)
        return exit_code

    if not rotations:
        raise MatrixRunError("No capture-capable master targets discovered")
    if getattr(args, "prime_then_immediate_role_switch", False):
        prime_exit_code = warm_prime_runtime_bridges(
            targets,
            run_dir,
            timeout=(
                getattr(args, "standby_launch_timeout", None)
                or args.timeout
            ),
            apk=args.apk,
            master_hosts=warm_master_hosts,
            fast_ios_launch=args.fast_ios_launch,
            xctrace_ios_launch=getattr(args, "xctrace_ios_launch", False),
            xctrace_time_limit_seconds=getattr(
                args,
                "xctrace_time_limit_seconds",
                28800,
            ),
            ios_profile_trust_retry_timeout=getattr(
                args,
                "ios_profile_trust_retry_timeout",
                0,
            ),
            ios_profile_trust_retry_interval=getattr(
                args,
                "ios_profile_trust_retry_interval",
                5,
            ),
        )
        if prime_exit_code != 0:
            print(run_dir)
            return prime_exit_code
    if (
        args.runtime_role_switch
        and args.reuse_running_bridges
        and getattr(args, "require_warm_bridges", False)
    ):
        missing_warm_bridges = missing_warm_runtime_bridges(targets)
        write_json(
            run_dir / "warm-bridge-preflight.json",
            {
                "status": "failed" if missing_warm_bridges else "passed",
                "missingWarmBridgeDeviceIds": [
                    entry["deviceId"] for entry in missing_warm_bridges
                ],
                "missingWarmBridges": missing_warm_bridges,
            },
        )
        require_warm_runtime_bridges(targets)
    needs_android_apk = requires_android_apk(targets)
    if needs_android_apk and not args.skip_build:
        build_android_apk(ndk_version=args.android_ndk_version)
    if needs_android_apk and not args.skip_install and not args.apk.exists():
        raise MatrixRunError(f"APK not found: {args.apk}")

    android_targets = [target for target in targets if target.platform == "android"]
    if not args.reuse_running_bridges:
        remove_android_forwards(android_targets)
        ensure_local_ports_free(targets)
    if warm_master_hosts is not None:
        selected_ids = {target.device_id for target in targets}
        master_hosts = {
            device_id: host
            for device_id, host in warm_master_hosts.items()
            if device_id in selected_ids
        }
        missing_master_hosts = [
            rotation.master.device_id
            for rotation in rotations
            if rotation.master.device_id not in master_hosts
        ]
        if missing_master_hosts:
            joined = ", ".join(sorted(missing_master_hosts))
            raise MatrixConfigError(
                f"Warm summary is missing masterHosts for: {joined}"
            )
    else:
        master_hosts = resolve_master_hosts(
            targets,
            macos_master_host=args.macos_master_host,
        )
    write_json(run_dir / "master-hosts.json", master_hosts)
    run_started_at = dt.datetime.now().isoformat()
    run_started = time.perf_counter()

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(android_targets))) as executor:
            futures = [
                executor.submit(
                    prepare_android_target,
                    target,
                    args.apk,
                    skip_install=args.skip_install,
                    reuse_running_bridge=args.reuse_running_bridges,
                )
                for target in android_targets
            ]
            for future in concurrent.futures.as_completed(futures):
                future.result()

        rotation_results: list[dict[str, Any]] = []
        standby_processes: dict[str, subprocess.Popen[str]] = {}
        try:
            if args.runtime_role_switch:
                if not args.reuse_running_bridges:
                    terminate_flutter_app_targets(targets)
                    for target in android_targets:
                        stop_android_target(target)
                if not (
                    args.reuse_running_bridges
                    and getattr(args, "require_warm_bridges", False)
                ):
                    standby_processes = launch_standby_targets(
                        targets,
                        run_dir / "standby-launch",
                        timeout=(
                            getattr(args, "standby_launch_timeout", None)
                            or args.timeout
                        ),
                        fast_ios_launch=args.fast_ios_launch,
                        xctrace_ios_launch=getattr(
                            args,
                            "xctrace_ios_launch",
                            False,
                        ),
                        xctrace_time_limit_seconds=getattr(
                            args,
                            "xctrace_time_limit_seconds",
                            28800,
                        ),
                        reuse_running_bridges=args.reuse_running_bridges,
                    )

            for cycle_index in range(repeat_role_switch_cycles):
                if repeat_role_switch_cycles > 1:
                    print(
                        f"=== Cycle {cycle_index + 1}/{repeat_role_switch_cycles} ===",
                        flush=True,
                    )
                for rotation in rotations:
                    print(
                        f"=== Rotation master {rotation.master.device_id} ===",
                        flush=True,
                    )
                    rotation_dir = (
                        run_dir / f"cycle-{cycle_index + 1:02d}" / rotation.slug
                        if repeat_role_switch_cycles > 1
                        else run_dir / rotation.slug
                    )
                    rotation_dir.mkdir(parents=True, exist_ok=True)
                    processes: dict[str, subprocess.Popen[str]] = {}
                    phase_timings: dict[str, Any] = {}
                    runtime_switch_snapshot: dict[str, Any] | None = None
                    try:
                        if args.runtime_role_switch:
                            master_host = master_hosts.get(rotation.master.device_id)
                            if not master_host:
                                raise MatrixRunError(
                                    "No master host resolved for "
                                    f"{rotation.master.device_id}"
                                )
                            switch_started_at = dt.datetime.now().isoformat()
                            switch_started = time.perf_counter()
                            switch_responses = apply_runtime_role_switch(
                                rotation,
                                targets=targets,
                                master_host=master_host,
                                timeout=args.timeout,
                                stage_slaves_after_master_ready=getattr(
                                    args,
                                    "stage_slaves_after_master_ready",
                                    False,
                                ),
                                master_ready_timeout=(
                                    args.role_switch_verify_timeout
                                ),
                            )
                            switch_elapsed = time.perf_counter() - switch_started
                            record_phase_timing(
                                phase_timings,
                                "set_role",
                                started_at=switch_started_at,
                                elapsed_seconds=switch_elapsed,
                            )
                            runtime_switch_snapshot = (
                                build_runtime_role_switch_snapshot(
                                    switch_responses,
                                    started_at=switch_started_at,
                                    elapsed_seconds=switch_elapsed,
                                )
                            )
                            write_json(
                                rotation_dir / "runtime-role-switch.json",
                                runtime_switch_snapshot,
                            )
                            if max_set_role_request_start_skew_ms is not None:
                                parallel_start_skew = runtime_switch_snapshot.get(
                                    "parallelRequestStartSkewMs"
                                )
                                if (
                                    isinstance(parallel_start_skew, (int, float))
                                    and parallel_start_skew
                                    > max_set_role_request_start_skew_ms
                                ):
                                    raise MatrixRunError(
                                        "Runtime set_role request start skew "
                                        f"{parallel_start_skew}ms exceeded "
                                        f"{max_set_role_request_start_skew_ms}ms"
                                    )
                            if not getattr(
                                args,
                                "stage_slaves_after_master_ready",
                                False,
                            ):
                                timed_phase(
                                    phase_timings,
                                    "master_commands",
                                    lambda: wait_for_master_commands(
                                        rotation.master,
                                        timeout=args.role_switch_verify_timeout,
                                    ),
                                )
                        else:
                            terminate_flutter_app_targets(targets)
                            processes = launch_rotation(
                                rotation,
                                targets,
                                master_hosts,
                                rotation_dir,
                                timeout=args.timeout,
                                fast_ios_launch=args.fast_ios_launch,
                            )
                        if args.role_switch_only:
                            rotation_result = run_role_switch_only_flow(
                                rotation,
                                rotation_dir,
                                timeout=(
                                    args.role_switch_verify_timeout
                                    if args.runtime_role_switch
                                    else args.timeout
                                ),
                                master_hosts=master_hosts,
                                collect_logs=args.collect_role_switch_logs,
                                phase_timings=phase_timings,
                            )
                        else:
                            rotation_result = run_rotation_capture_flow(
                                rotation,
                                rotation_dir,
                                record_seconds=args.record_seconds,
                                timeout=args.timeout,
                                master_hosts=master_hosts,
                                capture_stage_timeout=args.capture_stage_timeout,
                                recording_ready_timeout=args.recording_ready_timeout,
                                stop_recording_timeout=args.stop_recording_timeout,
                            )
                            if phase_timings:
                                rotation_result["phaseTimings"] = dict(
                                    phase_timings
                                )
                        if repeat_role_switch_cycles > 1:
                            rotation_result["cycleIndex"] = cycle_index
                            rotation_result["cycleNumber"] = cycle_index + 1
                        if runtime_switch_snapshot is not None:
                            rotation_result["runtimeRoleSwitch"] = (
                                runtime_switch_snapshot
                            )
                        rotation_results.append(rotation_result)
                    except Exception as error:
                        rotation_result = {
                            **rotation_to_json(rotation),
                            "status": "failed",
                            "failures": [str(error)],
                            "targetResults": [],
                            "phaseTimings": dict(phase_timings),
                        }
                        if repeat_role_switch_cycles > 1:
                            rotation_result["cycleIndex"] = cycle_index
                            rotation_result["cycleNumber"] = cycle_index + 1
                        if runtime_switch_snapshot is not None:
                            rotation_result["runtimeRoleSwitch"] = (
                                runtime_switch_snapshot
                            )
                        write_json(rotation_dir / "summary.json", rotation_result)
                        rotation_results.append(rotation_result)
                    finally:
                        if phase_timings:
                            write_json(
                                rotation_dir / "phase-timings.json",
                                phase_timings,
                            )
                        stop_processes(processes)
                        if not args.runtime_role_switch:
                            terminate_flutter_app_targets(targets)
                            for target in android_targets:
                                stop_android_target(target)
                            time.sleep(2)
        finally:
            if not args.reuse_running_bridges:
                stop_processes(standby_processes)
            if not args.reuse_running_bridges:
                terminate_flutter_app_targets(targets)
                for target in android_targets:
                    stop_android_target(target)

        status = "passed"
        if any(result["status"] == "failed" for result in rotation_results):
            status = "failed"
        elif any(
            result["status"] == "completed_with_known_blockers"
            for result in rotation_results
        ):
            status = "completed_with_known_blockers"

        summary = {
            "status": status,
            "sharedBarrierPerRotation": True,
            "startedAt": run_started_at,
            "elapsedSeconds": round(time.perf_counter() - run_started, 3),
            "targetCount": len(targets),
            "captureTargetCount": sum(1 for target in targets if target.capture_enabled),
            "rotationCount": len(rotation_results),
            "repeatRoleSwitchCycles": repeat_role_switch_cycles,
            "runtimeRoleSwitch": args.runtime_role_switch,
            "roleSwitchOnly": args.role_switch_only,
            "stageSlavesAfterMasterReady": getattr(
                args,
                "stage_slaves_after_master_ready",
                False,
            ),
            "masterHosts": master_hosts,
            "targets": [target_to_json(target) for target in targets],
            "rotations": rotation_results,
            "phaseTimingStats": build_phase_timing_stats(rotation_results),
            "runtimeRoleSwitchTimingStats": (
                build_runtime_role_switch_timing_stats(rotation_results)
            ),
            "connectedClientRegistrationTimingStats": (
                build_connected_client_registration_timing_stats(
                    rotation_results,
                )
            ),
        }
        write_json(run_dir / "summary.json", summary)
        write_summary_markdown(run_dir, summary)
        if status == "passed" and args.reuse_running_bridges:
            write_latest_warm_summary_cache(
                args,
                run_dir,
                targets=targets,
                master_hosts=master_hosts,
                source_artifact=run_dir / "summary.json",
            )
        print(run_dir)
        return 1 if status == "failed" else 0
    finally:
        if not args.reuse_running_bridges:
            remove_android_forwards(android_targets)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ios-host",
        action="append",
        default=[],
        metavar="DEVICE_ID=HOST",
        help="Explicit bridge host for a physical iOS device. May repeat.",
    )
    parser.add_argument(
        "--auto-ios-bridge-hosts",
        action=argparse.BooleanOptionalAction,
        default=False,
        help=(
            "Scan likely LAN hosts for physical iOS automation bridges and "
            "adopt only identity-matched /healthz responses. Enabled by the "
            "immediate role-switch shortcuts unless --no-auto-ios-bridge-hosts "
            "is passed."
        ),
    )
    parser.add_argument(
        "--ios-bridge-scan-subnet",
        action="append",
        default=[],
        metavar="CIDR",
        help=(
            "Extra IPv4 subnet to scan for identity-matched physical iOS "
            "bridges when --auto-ios-bridge-hosts is enabled. May repeat."
        ),
    )
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--warm-summary",
        type=Path,
        help=(
            "Reuse targets and masterHosts from a previous rotating-matrix "
            "summary.json or run directory, skipping flutter/adb discovery and "
            "master-host probing."
        ),
    )
    parser.add_argument(
        "--use-latest-warm-summary",
        action=argparse.BooleanOptionalAction,
        default=None,
        help=(
            "Reuse the latest persisted warm bridge map instead of running "
            "Flutter/ADB discovery. Immediate role-switch shortcuts use this "
            "cache automatically when it exists; pass "
            "--no-use-latest-warm-summary to force fresh discovery."
        ),
    )
    parser.add_argument(
        "--latest-warm-summary",
        type=Path,
        default=DEFAULT_LATEST_WARM_SUMMARY,
        help=(
            "Path to the persisted latest warm bridge map used by "
            "--use-latest-warm-summary and updated after successful warm "
            "role-switch runs."
        ),
    )
    parser.add_argument(
        "--update-latest-warm-summary",
        action=argparse.BooleanOptionalAction,
        default=True,
        help=(
            "Update the latest warm bridge map after a successful warm "
            "role-switch run. Disable with --no-update-latest-warm-summary."
        ),
    )
    parser.add_argument(
        "--target-id",
        action="append",
        default=[],
        help=(
            "Only include this device ID in the run. May repeat. Filtering "
            "happens before physical iOS host validation."
        ),
    )
    parser.add_argument(
        "--expect-target-id",
        action="append",
        default=[],
        help=(
            "Require this device ID to be present after discovery/warm-summary "
            "loading and target filtering. May repeat. The runner fails before "
            "build/install/launch when an expected target is absent."
        ),
    )
    parser.add_argument(
        "--master-id",
        action="append",
        default=[],
        help="Only run rotations where this device ID is master. May repeat.",
    )
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--skip-install", action="store_true")
    parser.add_argument("--apk", type=Path, default=DEFAULT_APK)
    parser.add_argument(
        "--android-ndk-version",
        help=(
            "Override the Gradle hydracamNdkVersion property for this build. "
            "Useful when the default repo NDK is not installed locally."
        ),
    )
    parser.add_argument("--android-port-base", type=int, default=DEFAULT_ANDROID_PORT_BASE)
    parser.add_argument("--local-port-base", type=int, default=DEFAULT_LOCAL_PORT_BASE)
    parser.add_argument("--physical-ios-port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--record-seconds", type=float, default=DEFAULT_RECORD_SECONDS)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument(
        "--standby-launch-timeout",
        type=float,
        help=(
            "Maximum seconds to wait for initial standby bridges in runtime "
            "role-switch mode. Defaults to --timeout."
        ),
    )
    parser.add_argument(
        "--role-switch-verify-timeout",
        type=float,
        default=DEFAULT_ROLE_SWITCH_VERIFY_TIMEOUT_SECONDS,
        help=(
            "Maximum seconds to wait after a warm runtime role switch for "
            "the promoted master commands and expected client connections."
        ),
    )
    parser.add_argument(
        "--capture-stage-timeout",
        type=float,
        default=DEFAULT_CAPTURE_STAGE_TIMEOUT_SECONDS,
        help=(
            "Maximum seconds to wait for start-session/photo/end-session state "
            "on all targets in a rotation."
        ),
    )
    parser.add_argument(
        "--recording-ready-timeout",
        type=float,
        default=DEFAULT_RECORDING_READY_TIMEOUT_SECONDS,
        help=(
            "Maximum seconds to wait for all required targets to report "
            "isRecording before the runner starts the record-seconds timer."
        ),
    )
    parser.add_argument(
        "--stop-recording-timeout",
        type=float,
        default=DEFAULT_STOP_RECORDING_TIMEOUT_SECONDS,
        help=(
            "Maximum seconds to wait for all required targets to save a video "
            "after stop_recording."
        ),
    )
    parser.add_argument(
        "--macos-master-host",
        help="Explicit Wi-Fi/LAN IP other devices should use when macOS is master.",
    )
    parser.add_argument(
        "--fast-ios-launch",
        action="store_true",
        help=(
            "Use preinstalled physical iOS apps launched through devicectl "
            "runtime environment instead of flutter run."
        ),
    )
    parser.add_argument(
        "--ios-profile-build-install",
        action="store_true",
        help=(
            "Build and install an automation-enabled iOS Profile app on "
            "selected physical iOS devices before launch. Use this once to "
            "make --fast-ios-launch viable without Flutter tooling."
        ),
    )
    parser.add_argument(
        "--ios-profile-app",
        type=Path,
        default=IOS_PROFILE_APP,
        help="Path to the built iOS Profile Runner.app to install.",
    )
    parser.add_argument(
        "--xctrace-ios-launch",
        action="store_true",
        help=(
            "Use xctrace to launch preinstalled physical iOS apps. This is "
            "useful for older devices that appear in xcdevice but not devicectl."
        ),
    )
    parser.add_argument(
        "--xctrace-time-limit-seconds",
        type=int,
        default=28800,
        help=(
            "How long xctrace should keep a launched physical iOS app alive. "
            "Only used with --xctrace-ios-launch."
        ),
    )
    parser.add_argument(
        "--ios-profile-trust-retry-timeout",
        type=float,
        default=0,
        help=(
            "When warm-prime sees ios_profile_not_trusted, keep retrying the "
            "missing physical iOS bridge for this many seconds so the operator "
            "can trust the developer profile on-device without restarting the "
            "matrix command. Defaults to 0, which fails fast."
        ),
    )
    parser.add_argument(
        "--ios-profile-trust-retry-interval",
        type=float,
        default=5,
        help=(
            "Seconds between ios_profile_not_trusted warm-prime retry attempts."
        ),
    )
    parser.add_argument(
        "--immediate-role-switch",
        action="store_true",
        help=(
            "Shortcut for the fastest warm role-switch proof: runtime role "
            "switching, role-switch-only, reuse running bridges, require warm "
            "bridges, skip build, and skip install. It fails fast instead of "
            "falling back to cold launch when a selected bridge is missing."
        ),
    )
    parser.add_argument(
        "--warm-prime-only",
        action="store_true",
        help=(
            "Only try to warm selected missing automation bridges, then write "
            "warm-bridge-prime.json. This reuses already-running bridges, "
            "skips build/install, and does not run role rotations."
        ),
    )
    parser.add_argument(
        "--prime-then-immediate-role-switch",
        action="store_true",
        help=(
            "Try to warm missing selected bridges first, then run the immediate "
            "role-switch proof only if every selected bridge is warm. This "
            "skips build/install and writes warm-bridge-prime.json before any "
            "rotation artifacts."
        ),
    )
    parser.add_argument(
        "--runtime-role-switch",
        action="store_true",
        help=(
            "Launch every target once in standby, then rotate master/slave "
            "roles through the automation bridge instead of relaunching apps."
        ),
    )
    parser.add_argument(
        "--role-switch-only",
        action="store_true",
        help=(
            "Stop after proving the selected master exposes control commands "
            "and sees every selected client. No photo or video commands run."
        ),
    )
    parser.add_argument(
        "--repeat-role-switch-cycles",
        type=int,
        default=1,
        help=(
            "Repeat all selected rotations this many times in one hot runner. "
            "Values above 1 require runtime role-switch role-switch-only mode."
        ),
    )
    parser.add_argument(
        "--max-set-role-request-start-skew-ms",
        type=float,
        help=(
            "Fail a runtime role-switch rotation if parallel set_role requests "
            "do not begin within this many milliseconds of each other."
        ),
    )
    parser.add_argument(
        "--stage-slaves-after-master-ready",
        action="store_true",
        help=(
            "In runtime role-switch mode, set the new master first, wait until "
            "it exposes master commands, then set all slaves in a parallel "
            "batch. This reduces slave connection races against slow master "
            "server startup while preserving parallel slave dispatch."
        ),
    )
    parser.add_argument(
        "--fully-parallel-role-switch",
        action="store_true",
        help=(
            "Diagnostic mode for runtime role-switch proofs: send the promoted "
            "master and all slaves in one parallel set_role batch. The "
            "immediate shortcuts default to staging the master first because "
            "current evidence shows that is faster end-to-end."
        ),
    )
    parser.add_argument(
        "--collect-role-switch-logs",
        action="store_true",
        help=(
            "Collect per-target logs even for successful role-switch-only "
            "rotations. By default logs are collected only on failures."
        ),
    )
    parser.add_argument(
        "--reuse-running-bridges",
        action="store_true",
        help=(
            "When a target's automation bridge is already healthy and exposes "
            "set_role, reuse it instead of terminating and relaunching the app."
        ),
    )
    parser.add_argument(
        "--require-warm-bridges",
        action="store_true",
        help=(
            "In runtime role-switch reuse mode, fail before build/install/launch "
            "unless every selected target already exposes an identity-matched "
            "set_role bridge."
        ),
    )
    args = parser.parse_args(list(argv))
    if args.warm_summary is not None and args.use_latest_warm_summary is True:
        parser.error("--warm-summary cannot be combined with --use-latest-warm-summary")
    args._hydracam_explicit_skip_build = _argv_has_option(argv, "--skip-build")
    args._hydracam_explicit_skip_install = _argv_has_option(argv, "--skip-install")
    args._hydracam_explicit_auto_ios_bridge_hosts = _argv_has_option(
        argv,
        "--auto-ios-bridge-hosts",
    )
    args._hydracam_explicit_no_auto_ios_bridge_hosts = _argv_has_option(
        argv,
        "--no-auto-ios-bridge-hosts",
    )
    apply_immediate_role_switch_defaults(args, argv=argv)
    return apply_warm_prime_defaults(args)


def main(argv: Sequence[str]) -> int:
    try:
        return run_matrix(parse_args(argv))
    except (MatrixConfigError, MatrixRunError, ReproError, subprocess.CalledProcessError) as error:
        print(f"run_rotating_master_slave_matrix failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
