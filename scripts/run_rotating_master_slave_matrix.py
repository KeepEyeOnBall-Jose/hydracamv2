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
import json
import re
import subprocess
import sys
import tempfile
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
from run_parallel_device_matrix import (
    ANDROID_PERMISSIONS,
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
    apply_settings,
    await_session_value,
    build_android_apk,
    classify_known_blocker,
    collect_android_logcat,
    discover_targets,
    ensure_local_ports_free,
    remove_android_forwards,
    run_command,
    target_to_json,
    write_json,
)

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONNECTION_TIMEOUT_SECONDS = 45.0
IOS_BUNDLE_ID = "com.vectorblanco.hydracam.dev"


@dataclasses.dataclass(frozen=True)
class MatrixRotation:
    master: MatrixTarget
    clients: list[MatrixTarget]

    @property
    def slug(self) -> str:
        value = f"master-{self.master.platform}-{self.master.device_id}"
        return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-").lower()


def now_slug() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M-rotating-master-slave-matrix")


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
) -> dict[str, Any]:
    return {
        "status": "dry_run",
        "sharedBarrierPerRotation": True,
        "runtimeRoleSwitch": runtime_role_switch,
        "roleSwitchOnly": role_switch_only,
        "targetCount": len(targets),
        "captureTargetCount": sum(1 for target in targets if target.capture_enabled),
        "rotationCount": len(rotations),
        "targets": [target_to_json(target) for target in targets],
        "rotations": [rotation_to_json(rotation) for rotation in rotations],
    }


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
        "",
        "| Master | Status | Clients | Notes |",
        "| --- | --- | --- | --- |",
    ]
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


def prepare_android_target(target: MatrixTarget, apk: Path, *, skip_install: bool) -> None:
    if not skip_install:
        run_command(["adb", "-s", target.device_id, "install", "-r", str(apk)])
    for permission in ANDROID_PERMISSIONS:
        run_command(
            ["adb", "-s", target.device_id, "shell", "pm", "grant", PACKAGE_NAME, permission],
            check=False,
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


def stop_android_target(target: MatrixTarget) -> None:
    if target.platform == "android":
        run_command(
            ["adb", "-s", target.device_id, "shell", "am", "force-stop", PACKAGE_NAME],
            check=False,
        )


def launch_android_target(
    target: MatrixTarget,
    *,
    role: str,
    master_ip: str | None,
) -> None:
    stop_android_target(target)
    run_command(build_android_start_command(target, role=role, master_ip=master_ip))


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
    wait_for_flutter_bridge(target, process, time.time() + timeout)
    detach_flutter(process)
    return None


def build_ios_fast_launch_command(
    target: MatrixTarget,
    *,
    role: str,
    master_ip: str | None,
) -> list[str]:
    environment = {
        "HYDRACAM_AUTOMATION_ROLE": role,
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
    wait_for_bridge(target.bridge_url, time.time() + timeout)


def wait_for_flutter_bridge(
    target: MatrixTarget,
    process: subprocess.Popen[str],
    deadline: float,
) -> None:
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            health = request_json(target.bridge_url, "GET", "/healthz", timeout=3)
            if health.get("status") == "ok":
                return
        except ReproError as error:
            last_error = error
        if process.poll() is not None:
            raise ReproError(
                f"flutter run for {target.device_id} exited before "
                f"{target.bridge_url}/healthz became reachable: {last_error}"
            )
        time.sleep(1)
    raise ReproError(f"Automation bridge did not become healthy at {target.bridge_url}")


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
) -> subprocess.Popen[str] | None:
    if target.platform == "android":
        launch_android_target(target, role=role, master_ip=master_ip)
        wait_for_bridge(target.bridge_url, time.time() + timeout)
        return None
    if target.platform == "ios_physical" and fast_ios_launch:
        launch_ios_fast_target(
            target,
            rotation_dir,
            role=role,
            master_ip=master_ip,
            timeout=timeout,
        )
        return None
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
        time.sleep(1)
    raise ReproError(
        "Timed out waiting for connected slave clients on "
        f"{master.device_id}: expected {expected_count}, last={last_payload}"
    )


def apply_runtime_role_switch(
    rotation: MatrixRotation,
    *,
    targets: Sequence[MatrixTarget],
    master_host: str,
    timeout: float,
) -> dict[str, Any]:
    payloads = build_runtime_role_payloads(rotation, master_host=master_host)
    targets_by_id = {target.device_id: target for target in targets}
    deadline = time.time() + timeout
    responses: dict[str, Any] = {}

    def post_role(device_id: str, payload: dict[str, Any]) -> tuple[str, Any]:
        target = targets_by_id[device_id]
        return (
            device_id,
            post_command(target.bridge_url, "set_role", payload, deadline),
        )

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(payloads))) as executor:
        futures = [
            executor.submit(post_role, device_id, payload)
            for device_id, payload in payloads.items()
        ]
        for future in concurrent.futures.as_completed(futures):
            device_id, response = future.result()
            responses[device_id] = response
    return responses


def build_runtime_role_switch_snapshot(
    responses: Mapping[str, Any],
    *,
    started_at: str,
    elapsed_seconds: float,
) -> dict[str, Any]:
    return {
        "startedAt": started_at,
        "elapsedMs": round(elapsed_seconds * 1000, 3),
        "responses": responses,
    }


def wait_for_master_commands(master: MatrixTarget, *, timeout: float) -> None:
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
        time.sleep(0.5)
    raise ReproError(
        f"Timed out waiting for {master.device_id} to expose master commands: "
        f"{last_health}"
    )


def launch_standby_targets(
    targets: Sequence[MatrixTarget],
    run_dir: Path,
    *,
    timeout: float,
    fast_ios_launch: bool,
) -> dict[str, subprocess.Popen[str]]:
    processes: dict[str, subprocess.Popen[str]] = {}
    android_targets = [target for target in targets if target.platform == "android"]
    flutter_targets = [
        target
        for target in targets
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
        )
        if process is not None:
            processes[target.device_id] = process

    deadline = time.time() + timeout
    for target in targets:
        wait_for_bridge(target.bridge_url, deadline)
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
    for target in targets:
        if not required(target):
            snapshots[target.device_id] = {"status": "skipped"}
            continue
        try:
            snapshot = await_session_value(target, predicate, timeout=timeout)
            snapshots[target.device_id] = snapshot
        except Exception as error:
            _add_failure(states, target, stage, error)
            snapshots[target.device_id] = {
                "status": "failed",
                "error": str(error),
            }
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


def apply_rotation_settings(target: MatrixTarget, master: MatrixTarget) -> dict[str, Any]:
    original_master_should_record = None
    if target.device_id == master.device_id and master.device_id == S7_SERIAL:
        original_master_should_record = False
    if original_master_should_record is None:
        return apply_settings(target)

    request_json(
        target.bridge_url,
        "POST",
        "/settings",
        {
            "masterShouldRecord": original_master_should_record,
            "timerDuration": 0,
            "autoplayVideoOnMaster": False,
            "flashForVideoAnnounce": False,
            "autoUploadMaterials": False,
            "cameraLensPreference": target.lens,
            "videoCaptureProfile": target.profile,
        },
        timeout=20,
    )
    return request_json(target.bridge_url, "GET", "/settings", timeout=20)


def run_rotation_capture_flow(
    rotation: MatrixRotation,
    rotation_dir: Path,
    *,
    record_seconds: float,
    timeout: float,
) -> dict[str, Any]:
    targets = [rotation.master, *rotation.clients]
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
        settings: dict[str, Any] = {}
        for target in targets:
            settings[target.device_id] = apply_rotation_settings(target, rotation.master)
        snapshots["settings"] = settings

        snapshots["connected_clients"] = wait_connected_clients(
            rotation.master,
            expected_count=len(rotation.clients),
            timeout=DEFAULT_CONNECTION_TIMEOUT_SECONDS,
        )

        session_id = f"rotation-{rotation.master.device_id}-{int(time.time())}"
        command_times["start_local_session"] = dt.datetime.now().isoformat()
        snapshots["start_local_session"] = post_command(
            rotation.master.bridge_url,
            "start_local_session",
            {"sessionId": session_id},
            deadline,
        )
        snapshots["after_start_session"] = wait_for_target_stage(
            targets,
            states,
            "start_session",
            lambda payload: payload.get("isActive") is True,
            timeout=25,
            required=lambda target: True,
        )

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
            timeout=45,
            required=_target_requires_media,
        )

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
            timeout=55,
            required=_target_requires_media,
        )

        time.sleep(record_seconds)
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
            timeout=60,
            required=_target_requires_media,
        )

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
            timeout=30,
            required=lambda target: True,
        )
    except Exception as error:
        _add_failure(states, rotation.master, "rotation", error)
        snapshots["rotation_error"] = str(error)
    finally:
        snapshots["logs"] = collect_target_logs(rotation_dir, targets, states)

    target_results = finalize_target_states(states)
    status = "passed"
    if any(result["status"] == "failed" for result in target_results):
        status = "failed"
    elif any(result["status"] == "expected_blocker" for result in target_results):
        status = "completed_with_known_blockers"
    rotation_result = {
        **rotation_to_json(rotation),
        "status": status,
        "barrierReleasedAt": command_times.get("start_local_session"),
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
) -> dict[str, Any]:
    targets = [rotation.master, *rotation.clients]
    states: dict[str, dict[str, Any]] = {
        target.device_id: {
            "target": target_to_json(target),
            "failures": [],
            "knownBlocker": target.known_blocker,
        }
        for target in targets
    }
    snapshots: dict[str, Any] = {}

    try:
        snapshots["connected_clients"] = wait_connected_clients(
            rotation.master,
            expected_count=len(rotation.clients),
            timeout=timeout,
        )
    except Exception as error:
        _add_failure(states, rotation.master, "role_switch", error)
        snapshots["role_switch_error"] = str(error)
    finally:
        snapshots["logs"] = collect_target_logs(rotation_dir, targets, states)

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
        wait_for_bridge(target.bridge_url, deadline)
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
        "--filter",
        "executable.path CONTAINS 'HydraCam'",
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
        value = process.get("processIdentifier", process.get("pid"))
        if isinstance(value, int):
            process_ids.append(value)
    return process_ids


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
    targets = filter_targets_by_device_ids(discover_targets(args), args.target_id)
    rotations = filter_rotations_by_master_ids(
        build_rotations(targets),
        args.master_id,
    )
    run_dir = args.run_dir or REPO_ROOT / "logs" / "verification-runs" / now_slug()
    run_dir.mkdir(parents=True, exist_ok=True)

    if args.dry_run:
        summary = build_dry_run_summary(
            targets,
            rotations,
            runtime_role_switch=args.runtime_role_switch,
            role_switch_only=args.role_switch_only,
        )
        write_json(run_dir / "summary.json", summary)
        write_summary_markdown(run_dir, summary)
        print(json.dumps(summary, indent=2, sort_keys=True))
        return 0

    if not rotations:
        raise MatrixRunError("No capture-capable master targets discovered")
    needs_android_apk = requires_android_apk(targets)
    if needs_android_apk and not args.skip_build:
        build_android_apk()
    if needs_android_apk and not args.apk.exists():
        raise MatrixRunError(f"APK not found: {args.apk}")

    android_targets = [target for target in targets if target.platform == "android"]
    remove_android_forwards(android_targets)
    ensure_local_ports_free(targets)
    master_hosts = resolve_master_hosts(
        targets,
        macos_master_host=args.macos_master_host,
    )
    write_json(run_dir / "master-hosts.json", master_hosts)

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(android_targets))) as executor:
            futures = [
                executor.submit(
                    prepare_android_target,
                    target,
                    args.apk,
                    skip_install=args.skip_install,
                )
                for target in android_targets
            ]
            for future in concurrent.futures.as_completed(futures):
                future.result()

        rotation_results: list[dict[str, Any]] = []
        standby_processes: dict[str, subprocess.Popen[str]] = {}
        try:
            if args.runtime_role_switch:
                terminate_flutter_app_targets(targets)
                for target in android_targets:
                    stop_android_target(target)
                standby_processes = launch_standby_targets(
                    targets,
                    run_dir / "standby-launch",
                    timeout=args.timeout,
                    fast_ios_launch=args.fast_ios_launch,
                )

            for rotation in rotations:
                print(f"=== Rotation master {rotation.master.device_id} ===", flush=True)
                rotation_dir = run_dir / rotation.slug
                rotation_dir.mkdir(parents=True, exist_ok=True)
                processes: dict[str, subprocess.Popen[str]] = {}
                try:
                    if args.runtime_role_switch:
                        master_host = master_hosts.get(rotation.master.device_id)
                        if not master_host:
                            raise MatrixRunError(
                                f"No master host resolved for {rotation.master.device_id}"
                            )
                        switch_started_at = dt.datetime.now().isoformat()
                        switch_started = time.perf_counter()
                        switch_responses = apply_runtime_role_switch(
                            rotation,
                            targets=targets,
                            master_host=master_host,
                            timeout=args.timeout,
                        )
                        write_json(
                            rotation_dir / "runtime-role-switch.json",
                            build_runtime_role_switch_snapshot(
                                switch_responses,
                                started_at=switch_started_at,
                                elapsed_seconds=time.perf_counter() - switch_started,
                            ),
                        )
                        wait_for_master_commands(rotation.master, timeout=20)
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
                        rotation_results.append(
                            run_role_switch_only_flow(
                                rotation,
                                rotation_dir,
                                timeout=args.timeout,
                            )
                        )
                    else:
                        rotation_results.append(
                            run_rotation_capture_flow(
                                rotation,
                                rotation_dir,
                                record_seconds=args.record_seconds,
                                timeout=args.timeout,
                            )
                        )
                except Exception as error:
                    rotation_result = {
                        **rotation_to_json(rotation),
                        "status": "failed",
                        "failures": [str(error)],
                        "targetResults": [],
                    }
                    write_json(rotation_dir / "summary.json", rotation_result)
                    rotation_results.append(rotation_result)
                finally:
                    stop_processes(processes)
                    if not args.runtime_role_switch:
                        terminate_flutter_app_targets(targets)
                        for target in android_targets:
                            stop_android_target(target)
                        time.sleep(2)
        finally:
            stop_processes(standby_processes)
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
            "targetCount": len(targets),
            "captureTargetCount": sum(1 for target in targets if target.capture_enabled),
            "rotationCount": len(rotation_results),
            "runtimeRoleSwitch": args.runtime_role_switch,
            "roleSwitchOnly": args.role_switch_only,
            "masterHosts": master_hosts,
            "targets": [target_to_json(target) for target in targets],
            "rotations": rotation_results,
        }
        write_json(run_dir / "summary.json", summary)
        write_summary_markdown(run_dir, summary)
        print(run_dir)
        return 1 if status == "failed" else 0
    finally:
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
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--dry-run", action="store_true")
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
        "--master-id",
        action="append",
        default=[],
        help="Only run rotations where this device ID is master. May repeat.",
    )
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--skip-install", action="store_true")
    parser.add_argument("--apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--android-port-base", type=int, default=DEFAULT_ANDROID_PORT_BASE)
    parser.add_argument("--local-port-base", type=int, default=DEFAULT_LOCAL_PORT_BASE)
    parser.add_argument("--physical-ios-port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--record-seconds", type=float, default=DEFAULT_RECORD_SECONDS)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
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
    return parser.parse_args(list(argv))


def main(argv: Sequence[str]) -> int:
    try:
        return run_matrix(parse_args(argv))
    except (MatrixConfigError, MatrixRunError, ReproError, subprocess.CalledProcessError) as error:
        print(f"run_rotating_master_slave_matrix failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
