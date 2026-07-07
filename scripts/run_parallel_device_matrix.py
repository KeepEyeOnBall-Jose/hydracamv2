#!/usr/bin/env python3
"""Run the HydraCam camera settings matrix through a shared capture barrier."""

from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import datetime as dt
import json
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Mapping, Sequence

from ios_capture_repro import (
    DEFAULT_PORT,
    ReproError,
    launch_flutter,
    post_command,
    request_json,
    stop_flutter,
    wait_for_bridge,
)

REPO_ROOT = Path(__file__).resolve().parents[1]
REMOTE_AUTOMATION_PORT = 4762
DEFAULT_ANDROID_PORT_BASE = 6400
DEFAULT_LOCAL_PORT_BASE = 4770
DEFAULT_RECORD_SECONDS = 4.0
DEFAULT_TIMEOUT_SECONDS = 180.0
DEFAULT_APK = REPO_ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"
PACKAGE_NAME = "com.amaia23.hydracam"
MAIN_ACTIVITY = f"{PACKAGE_NAME}/.MainActivity"
S7_SERIAL = "9885e6503930304946"
IPHONE_12_PRO_ID = "00008101-000A68811E43001E"
IPAD_5_ID = "8b406aa5c597eab4c4dfd9908f4a09b10a89ec63"

BASE_ANDROID_PERMISSIONS = (
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
)
ANDROID_WRITE_EXTERNAL_STORAGE_PERMISSION = "android.permission.WRITE_EXTERNAL_STORAGE"
ANDROID_READ_EXTERNAL_STORAGE_PERMISSION = "android.permission.READ_EXTERNAL_STORAGE"
ANDROID_READ_MEDIA_PERMISSIONS = (
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VIDEO",
)


class MatrixConfigError(RuntimeError):
    """Raised when the matrix cannot be configured safely."""


class MatrixRunError(RuntimeError):
    """Raised when the matrix cannot complete."""


@dataclasses.dataclass(frozen=True)
class FlutterDevice:
    label: str
    device_id: str
    platform: str
    runtime: str


@dataclasses.dataclass(frozen=True)
class MatrixTarget:
    device_id: str
    label: str
    platform: str
    runtime: str
    lens: str
    profile: str
    host: str
    bridge_port: int
    capture_enabled: bool
    expected_result: str
    known_blocker: str | None = None

    @property
    def bridge_url(self) -> str:
        return f"http://{self.host}:{self.bridge_port}"

    @property
    def slug(self) -> str:
        value = f"{self.platform}-{self.device_id}-{self.profile}-{self.lens}"
        return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-").lower()


def now_slug() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M-parallel-device-matrix")


def parse_flutter_devices(output: str) -> list[FlutterDevice]:
    devices: list[FlutterDevice] = []
    for line in output.splitlines():
        if "•" not in line:
            continue
        parts = [part.strip() for part in line.split("•")]
        if len(parts) < 4:
            continue
        label, device_id, platform, runtime = parts[:4]
        if not label or not device_id:
            continue
        devices.append(
            FlutterDevice(
                label=" ".join(label.split()),
                device_id=device_id,
                platform=platform,
                runtime=runtime,
            )
        )
    return devices


def parse_adb_device_serials(output: str) -> set[str]:
    serials: set[str] = set()
    for line in output.splitlines()[1:]:
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split()
        if len(parts) >= 2 and parts[1] == "device":
            serials.add(parts[0])
    return serials


def parse_ios_hosts(entries: Sequence[str]) -> dict[str, str]:
    hosts: dict[str, str] = {}
    for entry in entries:
        if "=" not in entry:
            raise MatrixConfigError(
                f"--ios-host requires DEVICE_ID=HOST, got {entry!r}"
            )
        device_id, host = entry.split("=", 1)
        device_id = device_id.strip()
        host = host.strip()
        if not device_id or not host:
            raise MatrixConfigError(
                f"--ios-host requires DEVICE_ID=HOST, got {entry!r}"
            )
        if host == "auto":
            raise MatrixConfigError("--ios-host must be explicit; auto is unsafe")
        hosts[device_id] = host
    return hosts


def _ios_profile_for(device: FlutterDevice) -> tuple[str, str]:
    if device.device_id == IPHONE_12_PRO_ID:
        return "ultraWide", "sport1080p60"
    return "autoBack", "standard1080p30"


def _is_ios_simulator(device: FlutterDevice) -> bool:
    return device.platform == "ios" and "simulator" in device.runtime.lower()


def _is_physical_ios(device: FlutterDevice) -> bool:
    return device.platform == "ios" and not _is_ios_simulator(device)


def _target_sort_key(target: MatrixTarget) -> tuple[int, str]:
    order = {
        "android": 0,
        "ios_physical": 1,
        "macos": 2,
        "ios_simulator": 3,
    }
    return (order.get(target.platform, 99), target.device_id)


def build_matrix_targets(
    flutter_devices_output: str,
    adb_devices_output: str,
    *,
    ios_hosts: Mapping[str, str],
    android_port_base: int = DEFAULT_ANDROID_PORT_BASE,
    local_port_base: int = DEFAULT_LOCAL_PORT_BASE,
    physical_ios_port: int = DEFAULT_PORT,
    include_device_ids: set[str] | None = None,
) -> list[MatrixTarget]:
    flutter_devices = parse_flutter_devices(flutter_devices_output)
    adb_serials = parse_adb_device_serials(adb_devices_output)
    targets: list[MatrixTarget] = []
    local_devices: list[tuple[FlutterDevice, str, bool, str]] = []
    android_index = 0
    missing_ios_hosts: list[str] = []

    for device in flutter_devices:
        if include_device_ids is not None and device.device_id not in include_device_ids:
            continue
        if device.device_id == "chrome" or device.platform == "web-javascript":
            continue
        if "android" in device.platform:
            if device.device_id not in adb_serials:
                continue
            targets.append(
                MatrixTarget(
                    device_id=device.device_id,
                    label=device.label,
                    platform="android",
                    runtime=device.runtime,
                    lens="autoBack",
                    profile="standard1080p30",
                    host="127.0.0.1",
                    bridge_port=android_port_base + android_index,
                    capture_enabled=True,
                    expected_result="capture",
                    known_blocker=(
                        "s7_exynos_camera_timeout"
                        if device.device_id == S7_SERIAL
                        else None
                    ),
                )
            )
            android_index += 1
            continue
        if _is_physical_ios(device):
            host = ios_hosts.get(device.device_id)
            if host is None:
                missing_ios_hosts.append(device.device_id)
                continue
            lens, profile = _ios_profile_for(device)
            targets.append(
                MatrixTarget(
                    device_id=device.device_id,
                    label=device.label,
                    platform="ios_physical",
                    runtime=device.runtime,
                    lens=lens,
                    profile=profile,
                    host=host,
                    bridge_port=physical_ios_port,
                    capture_enabled=True,
                    expected_result="capture",
                )
            )
            continue
        if device.device_id == "macos" or "darwin" in device.platform:
            local_devices.append((device, "macos", True, "capture"))
            continue
        if _is_ios_simulator(device):
            local_devices.append((device, "ios_simulator", False, "launch_only"))

    if missing_ios_hosts:
        joined = ", ".join(sorted(missing_ios_hosts))
        raise MatrixConfigError(
            f"Missing --ios-host for physical iOS device(s): {joined}"
        )
    local_order = {"macos": 0, "ios_simulator": 1}
    for local_index, (device, platform, capture_enabled, expected_result) in enumerate(
        sorted(local_devices, key=lambda entry: (local_order[entry[1]], entry[0].device_id))
    ):
        targets.append(
            MatrixTarget(
                device_id=device.device_id,
                label=device.label,
                platform=platform,
                runtime=device.runtime,
                lens="autoBack",
                profile="standard1080p30",
                host="127.0.0.1",
                bridge_port=local_port_base + local_index,
                capture_enabled=capture_enabled,
                expected_result=expected_result,
            )
        )
    sorted_targets = sorted(targets, key=_target_sort_key)
    if include_device_ids is not None:
        resolved_ids = {target.device_id for target in sorted_targets}
        missing_ids = sorted(include_device_ids - resolved_ids)
        if missing_ids:
            joined = ", ".join(missing_ids)
            raise MatrixConfigError(f"unknown or unsupported target-id(s): {joined}")
    return sorted_targets


def classify_known_blocker(device_id: str, log_text: str) -> str | None:
    if device_id != S7_SERIAL:
        return None
    lowered = log_text.lower()
    has_exynos = "exynoscamera3" in lowered
    has_camera2 = "camera2cameraimpl" in lowered or "camera2" in lowered
    has_timeout = "timeout" in lowered or "wait timed out" in lowered
    if has_exynos and has_camera2 and has_timeout:
        return "s7_exynos_camera_timeout"
    return None


def build_dry_run_summary(targets: Sequence[MatrixTarget]) -> dict[str, Any]:
    return {
        "status": "dry_run",
        "sharedBarrier": True,
        "targetCount": len(targets),
        "captureTargetCount": sum(1 for target in targets if target.capture_enabled),
        "targets": [target_to_json(target) for target in targets],
    }


def target_to_json(target: MatrixTarget) -> dict[str, Any]:
    return {
        "deviceId": target.device_id,
        "label": target.label,
        "platform": target.platform,
        "runtime": target.runtime,
        "lens": target.lens,
        "profile": target.profile,
        "bridgeUrl": target.bridge_url,
        "captureEnabled": target.capture_enabled,
        "expectedResult": target.expected_result,
        "knownBlocker": target.known_blocker,
    }


def parse_android_api_level(runtime: str) -> int | None:
    match = re.search(r"\bAPI\s+(\d+)\b", runtime)
    if not match:
        return None
    return int(match.group(1))


def android_permissions_for_target(target: MatrixTarget) -> tuple[str, ...]:
    api_level = parse_android_api_level(target.runtime)
    permissions = list(BASE_ANDROID_PERMISSIONS)
    if api_level is None:
        return tuple(permissions)
    if api_level <= 28:
        permissions.append(ANDROID_WRITE_EXTERNAL_STORAGE_PERMISSION)
    if api_level <= 32:
        permissions.append(ANDROID_READ_EXTERNAL_STORAGE_PERMISSION)
    else:
        permissions.extend(ANDROID_READ_MEDIA_PERMISSIONS)
    return tuple(permissions)


def run_command(
    command: Sequence[str],
    *,
    check: bool = True,
    capture_output: bool = False,
    timeout: float | None = None,
    env_overrides: Mapping[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    print("+ " + " ".join(command), flush=True)
    env = None
    if env_overrides:
        env = {
            **os.environ,
            **env_overrides,
        }
    return subprocess.run(
        list(command),
        cwd=REPO_ROOT,
        check=check,
        text=True,
        capture_output=capture_output,
        timeout=timeout,
        env=env,
    )


def discover_targets(args: argparse.Namespace) -> list[MatrixTarget]:
    flutter_output = run_command(
        ["flutter", "devices"],
        capture_output=True,
    ).stdout
    adb_output = run_command(
        ["adb", "devices", "-l"],
        capture_output=True,
    ).stdout
    return build_matrix_targets(
        flutter_output,
        adb_output,
        ios_hosts=parse_ios_hosts(args.ios_host),
        android_port_base=args.android_port_base,
        local_port_base=args.local_port_base,
        physical_ios_port=args.physical_ios_port,
        include_device_ids=(
            set(args.target_id)
            if getattr(args, "target_id", None)
            else None
        ),
    )


def write_json(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_summary_markdown(run_dir: Path, summary: Mapping[str, Any]) -> None:
    lines = [
        "# Parallel Device Matrix",
        "",
        f"- Status: `{summary.get('status')}`",
        f"- Shared barrier: `{summary.get('sharedBarrier')}`",
        f"- Barrier released at: `{summary.get('barrierReleasedAt', 'n/a')}`",
        "",
        "| Device | Platform | Target | Status | Notes |",
        "| --- | --- | --- | --- | --- |",
    ]
    for result in summary.get("results", summary.get("targets", [])):
        if not isinstance(result, Mapping):
            continue
        target = result.get("target", result)
        if not isinstance(target, Mapping):
            continue
        device = target.get("deviceId", "")
        platform = target.get("platform", "")
        lens = target.get("lens", "")
        profile = target.get("profile", "")
        status = result.get("status", target.get("expectedResult", ""))
        note = result.get("knownBlocker") or "; ".join(result.get("failures", []))
        lines.append(
            f"| `{device}` | `{platform}` | `{lens}` + `{profile}` | "
            f"`{status}` | {note} |"
        )
    (run_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def ensure_local_ports_free(targets: Sequence[MatrixTarget]) -> None:
    local_ports = {
        target.bridge_port
        for target in targets
        if target.host in {"127.0.0.1", "localhost"}
    }
    occupied: list[int] = []
    for port in sorted(local_ports):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                occupied.append(port)
    if occupied:
        ports = ", ".join(str(port) for port in occupied)
        raise MatrixRunError(f"Local automation port(s) already occupied: {ports}")


def build_android_apk(
    *,
    ndk_version: str | None = None,
    dart_defines: Sequence[str] | None = None,
) -> None:
    env_overrides = None
    if ndk_version:
        env_overrides = {
            "ORG_GRADLE_PROJECT_hydracamNdkVersion": ndk_version,
        }
    command = [
        "flutter",
        "build",
        "apk",
        "--debug",
        "--dart-define=HYDRACAM_AUTOMATION=true",
    ]
    command.extend(f"--dart-define={define}" for define in dart_defines or [])
    run_command(command, env_overrides=env_overrides)


def remove_android_forwards(targets: Sequence[MatrixTarget]) -> None:
    for target in targets:
        if target.platform != "android":
            continue
        run_command(
            ["adb", "-s", target.device_id, "forward", "--remove-all"],
            check=False,
        )


def setup_android_target(target: MatrixTarget, apk: Path, *, skip_install: bool) -> None:
    if not skip_install:
        run_command(["adb", "-s", target.device_id, "install", "-r", str(apk)])
    for permission in android_permissions_for_target(target):
        run_command(
            ["adb", "-s", target.device_id, "shell", "pm", "grant", PACKAGE_NAME, permission],
            check=False,
        )
    run_command(["adb", "-s", target.device_id, "shell", "am", "force-stop", PACKAGE_NAME])
    run_command(
        [
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
            "master",
            "--es",
            "automationTargetId",
            target.device_id,
        ]
    )
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


def launch_flutter_targets(
    targets: Sequence[MatrixTarget],
    run_dir: Path,
    *,
    timeout: float,
) -> dict[str, subprocess.Popen[str]]:
    processes: dict[str, subprocess.Popen[str]] = {}
    try:
        for target in targets:
            if target.platform not in {"ios_physical", "ios_simulator", "macos"}:
                continue
            target_dir = run_dir / target.slug
            target_dir.mkdir(parents=True, exist_ok=True)
            processes[target.device_id] = launch_flutter(
                target.device_id,
                target_dir / "flutter-run.log",
                port=target.bridge_port,
            )
            wait_for_bridge(target.bridge_url, time.time() + timeout)
        return processes
    except Exception:
        for process in processes.values():
            stop_flutter(process)
        raise


def apply_settings(target: MatrixTarget) -> dict[str, Any]:
    request_json(
        target.bridge_url,
        "POST",
        "/settings",
        {
            "masterShouldRecord": True,
            "timerDuration": 0,
            "autoplayVideoOnMaster": False,
            "flashForVideoAnnounce": False,
            "autoUploadMaterials": True,
            "cameraLensPreference": target.lens,
            "videoCaptureProfile": target.profile,
        },
        timeout=20,
    )
    return request_json(target.bridge_url, "GET", "/settings", timeout=20)


def await_session_value(
    target: MatrixTarget,
    predicate,
    *,
    timeout: float,
    interval: float = 1.0,
) -> dict[str, Any]:
    deadline = time.time() + timeout
    last_payload: dict[str, Any] = {}
    while time.time() < deadline:
        last_payload = request_json(target.bridge_url, "GET", "/session", timeout=10)
        if predicate(last_payload):
            return last_payload
        time.sleep(interval)
    raise ReproError(f"Timed out waiting for session state on {target.device_id}: {last_payload}")


def collect_android_logcat(
    target: MatrixTarget,
    target_dir: Path,
    *,
    tail: int = 400,
) -> str:
    if target.platform != "android":
        return ""
    result = run_command(
        ["adb", "-s", target.device_id, "logcat", "-d", "-t", str(tail)],
        check=False,
        capture_output=True,
    )
    text = (result.stdout or "") + (result.stderr or "")
    (target_dir / "logcat-tail.txt").write_text(text, encoding="utf-8")
    return text


def run_capture_flow(
    target: MatrixTarget,
    target_dir: Path,
    *,
    record_seconds: float,
    timeout: float,
) -> dict[str, Any]:
    target_dir.mkdir(parents=True, exist_ok=True)
    deadline = time.time() + timeout
    snapshots: dict[str, Any] = {}
    command_times: dict[str, str] = {}
    try:
        session_id = f"parallel-{target.slug}-{int(time.time())}"
        command_times["start_session"] = dt.datetime.now().isoformat()
        snapshots["start_session"] = post_command(
            target.bridge_url,
            "start_session",
            {"sessionId": session_id},
            deadline,
        )
        snapshots["after_start_session"] = await_session_value(
            target,
            lambda payload: payload.get("isActive") is True,
            timeout=20,
        )

        command_times["take_photo"] = dt.datetime.now().isoformat()
        snapshots["take_photo"] = post_command(
            target.bridge_url,
            "take_photo",
            {"showCountdown": False},
            deadline,
        )
        snapshots["after_take_photo"] = await_session_value(
            target,
            lambda payload: int(payload.get("photoCount", 0)) >= 1,
            timeout=30,
        )

        command_times["start_recording"] = dt.datetime.now().isoformat()
        snapshots["start_recording"] = post_command(
            target.bridge_url,
            "start_recording",
            {},
            deadline,
        )
        snapshots["after_start_recording"] = await_session_value(
            target,
            lambda payload: payload.get("isRecording") is True,
            timeout=45,
        )

        time.sleep(record_seconds)
        command_times["stop_recording"] = dt.datetime.now().isoformat()
        snapshots["stop_recording"] = post_command(
            target.bridge_url,
            "stop_recording",
            {},
            deadline,
        )
        snapshots["after_stop_recording"] = await_session_value(
            target,
            lambda payload: int(payload.get("videoCount", 0)) >= 1
            and payload.get("isRecording") is False,
            timeout=45,
        )

        command_times["end_session"] = dt.datetime.now().isoformat()
        snapshots["end_session"] = post_command(
            target.bridge_url,
            "end_session",
            {},
            deadline,
        )
        snapshots["after_end_session"] = await_session_value(
            target,
            lambda payload: payload.get("isActive") is False,
            timeout=20,
        )
        snapshots["logs"] = request_json(target.bridge_url, "GET", "/logs", timeout=20)
        write_json(target_dir / "automation-snapshots.json", snapshots)
        result = {
            "target": target_to_json(target),
            "status": "passed",
            "failures": [],
            "commandTimes": command_times,
            "traceFilePath": snapshots["logs"].get("traceFilePath"),
        }
        write_json(target_dir / "summary.json", result)
        return result
    except Exception as error:
        log_text = str(error)
        try:
            logs = request_json(target.bridge_url, "GET", "/logs", timeout=10)
            snapshots["logs"] = logs
            log_text += "\n" + json.dumps(logs)
        except Exception:
            pass
        log_text += "\n" + collect_android_logcat(target, target_dir)
        write_json(target_dir / "automation-snapshots.json", snapshots)
        blocker = classify_known_blocker(target.device_id, log_text)
        status = "expected_blocker" if blocker else "failed"
        result = {
            "target": target_to_json(target),
            "status": status,
            "failures": [str(error)],
            "knownBlocker": blocker,
            "commandTimes": command_times,
        }
        write_json(target_dir / "summary.json", result)
        return result


def run_launch_only_probe(target: MatrixTarget, target_dir: Path) -> dict[str, Any]:
    target_dir.mkdir(parents=True, exist_ok=True)
    snapshots: dict[str, Any] = {}
    failures: list[str] = []
    try:
        snapshots["health"] = request_json(target.bridge_url, "GET", "/healthz", timeout=10)
        snapshots["settings"] = apply_settings(target)
        snapshots["logs"] = request_json(target.bridge_url, "GET", "/logs", timeout=20)
    except Exception as error:
        failures.append(str(error))
    write_json(target_dir / "automation-snapshots.json", snapshots)
    result = {
        "target": target_to_json(target),
        "status": "launch_only" if not failures else "failed",
        "failures": failures,
        "traceFilePath": snapshots.get("logs", {}).get("traceFilePath"),
    }
    write_json(target_dir / "summary.json", result)
    return result


def command_skew_seconds(results: Sequence[Mapping[str, Any]], command: str) -> float | None:
    timestamps: list[dt.datetime] = []
    for result in results:
        raw = result.get("commandTimes", {})
        if not isinstance(raw, Mapping):
            continue
        value = raw.get(command)
        if not isinstance(value, str):
            continue
        try:
            timestamps.append(dt.datetime.fromisoformat(value))
        except ValueError:
            continue
    if len(timestamps) < 2:
        return None
    return (max(timestamps) - min(timestamps)).total_seconds()


def run_matrix(args: argparse.Namespace) -> int:
    targets = discover_targets(args)
    run_dir = args.run_dir or REPO_ROOT / "logs" / "verification-runs" / now_slug()
    run_dir.mkdir(parents=True, exist_ok=True)

    if args.dry_run:
        summary = build_dry_run_summary(targets)
        write_json(run_dir / "summary.json", summary)
        write_summary_markdown(run_dir, summary)
        print(json.dumps(summary, indent=2, sort_keys=True))
        return 0

    if not args.skip_build:
        build_android_apk()
    if not args.apk.exists():
        raise MatrixRunError(f"APK not found: {args.apk}")
    android_targets = [target for target in targets if target.platform == "android"]
    flutter_targets = [
        target
        for target in targets
        if target.platform in {"ios_physical", "ios_simulator", "macos"}
    ]
    remove_android_forwards(android_targets)
    ensure_local_ports_free(targets)
    processes: dict[str, subprocess.Popen[str]] = {}
    results: list[dict[str, Any]] = []
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(android_targets))) as executor:
            futures = [
                executor.submit(setup_android_target, target, args.apk, skip_install=args.skip_install)
                for target in android_targets
            ]
            for future in concurrent.futures.as_completed(futures):
                future.result()

        processes = launch_flutter_targets(
            flutter_targets,
            run_dir,
            timeout=args.timeout,
        )
        deadline = time.time() + args.timeout
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(targets))) as executor:
            health_futures = [
                executor.submit(wait_for_bridge, target.bridge_url, deadline)
                for target in targets
            ]
            for future in concurrent.futures.as_completed(health_futures):
                future.result()

        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(targets))) as executor:
            settings_futures = {
                executor.submit(apply_settings, target): target for target in targets
            }
            for future in concurrent.futures.as_completed(settings_futures):
                target = settings_futures[future]
                target_dir = run_dir / target.slug
                write_json(target_dir / "settings.json", future.result())

        barrier_released_at = dt.datetime.now().isoformat()
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(targets))) as executor:
            futures: list[concurrent.futures.Future[dict[str, Any]]] = []
            for target in targets:
                target_dir = run_dir / target.slug
                if target.capture_enabled:
                    futures.append(
                        executor.submit(
                            run_capture_flow,
                            target,
                            target_dir,
                            record_seconds=args.record_seconds,
                            timeout=args.timeout,
                        )
                    )
                else:
                    futures.append(executor.submit(run_launch_only_probe, target, target_dir))
            for future in concurrent.futures.as_completed(futures):
                results.append(future.result())

        status = "passed"
        if any(result["status"] == "failed" for result in results):
            status = "failed"
        elif any(result["status"] == "expected_blocker" for result in results):
            status = "completed_with_known_blockers"
        summary = {
            "status": status,
            "sharedBarrier": True,
            "barrierReleasedAt": barrier_released_at,
            "targetCount": len(targets),
            "captureTargetCount": sum(1 for target in targets if target.capture_enabled),
            "commandSkewSeconds": {
                "start_session": command_skew_seconds(results, "start_session"),
                "take_photo": command_skew_seconds(results, "take_photo"),
                "start_recording": command_skew_seconds(results, "start_recording"),
                "stop_recording": command_skew_seconds(results, "stop_recording"),
            },
            "results": sorted(
                results,
                key=lambda result: result["target"]["deviceId"],
            ),
        }
        write_json(run_dir / "summary.json", summary)
        write_summary_markdown(run_dir, summary)
        print(run_dir)
        return 1 if status == "failed" else 0
    finally:
        for process in processes.values():
            stop_flutter(process)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ios-host",
        action="append",
        default=[],
        metavar="DEVICE_ID=HOST",
        help="Explicit bridge host for a physical iOS device. May repeat.",
    )
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--skip-install", action="store_true")
    parser.add_argument("--apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--android-port-base", type=int, default=DEFAULT_ANDROID_PORT_BASE)
    parser.add_argument("--local-port-base", type=int, default=DEFAULT_LOCAL_PORT_BASE)
    parser.add_argument("--physical-ios-port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--record-seconds", type=float, default=DEFAULT_RECORD_SECONDS)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    return parser.parse_args(list(argv))


def main(argv: Sequence[str]) -> int:
    try:
        return run_matrix(parse_args(argv))
    except (MatrixConfigError, MatrixRunError, ReproError, subprocess.CalledProcessError) as error:
        print(f"run_parallel_device_matrix failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
