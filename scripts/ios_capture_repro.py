#!/usr/bin/env python3
"""Mechanical iOS/iPad capture repro through the HydraCam automation bridge."""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import ipaddress
import json
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PORT = 4762
DEFAULT_TIMEOUT_SECONDS = 90
DEFAULT_SCAN_SUBNET = "192.168.178.0/24"


class ReproError(RuntimeError):
    """Raised when the mechanical capture repro fails."""


def now_slug() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M-ios-capture-repro")


def request_json(
    bridge_url: str,
    method: str,
    path: str,
    payload: dict[str, Any] | None = None,
    *,
    timeout: float = 10,
) -> dict[str, Any]:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{bridge_url.rstrip('/')}{path}",
        data=body,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        details = error.read().decode("utf-8", errors="replace")
        raise ReproError(f"{method} {path} failed: HTTP {error.code}: {details}")
    except OSError as error:
        raise ReproError(f"{method} {path} failed: {error}") from error

    if not data:
        return {}
    decoded = json.loads(data)
    if not isinstance(decoded, dict):
        raise ReproError(f"{method} {path} returned non-object JSON: {decoded}")
    return decoded


def wait_for_bridge(bridge_url: str, deadline: float) -> None:
    while time.time() < deadline:
        try:
            health = request_json(bridge_url, "GET", "/healthz", timeout=3)
            if health.get("status") == "ok":
                return
        except ReproError:
            time.sleep(1)
    raise ReproError(f"Automation bridge did not become healthy at {bridge_url}")


def _port_is_open(host: str, port: int) -> bool:
    try:
      with socket.create_connection((host, port), timeout=0.35):
          return True
    except OSError:
      return False


def discover_bridge(
    port: int,
    subnet: str,
    deadline: float,
    *,
    required_command: str | None = None,
) -> str:
    network = ipaddress.ip_network(subnet, strict=False)
    hosts = [str(host) for host in network.hosts()]
    while time.time() < deadline:
        with concurrent.futures.ThreadPoolExecutor(max_workers=128) as executor:
            futures = {
                executor.submit(_port_is_open, host, port): host
                for host in hosts
            }
            for future in concurrent.futures.as_completed(futures):
                host = futures[future]
                if not future.result():
                    continue
                bridge_url = f"http://{host}:{port}"
                try:
                    health = request_json(bridge_url, "GET", "/healthz", timeout=2)
                except ReproError:
                    continue
                commands = health.get("commands", [])
                has_required_command = required_command is None or (
                    isinstance(commands, list) and required_command in commands
                )
                if health.get("status") == "ok" and has_required_command:
                    return bridge_url
        time.sleep(1)
    raise ReproError(
        f"Automation bridge was not discovered on {subnet} port {port}"
    )


def post_command(
    bridge_url: str,
    command: str,
    payload: dict[str, Any],
    deadline: float,
) -> dict[str, Any]:
    path = f"/commands/{command}"
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            return request_json(bridge_url, "POST", path, payload, timeout=30)
        except ReproError as error:
            last_error = error
            if "unknown_command" not in str(error):
                raise
            time.sleep(1)
    raise ReproError(f"Command {command} was not registered: {last_error}")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def build_flutter_launch_command(
    device_id: str,
    port: int,
    *,
    role: str = "master",
    master_ip: str | None = None,
    dart_defines: list[str] | None = None,
) -> list[str]:
    command = [
        "flutter",
        "run",
        "-d",
        device_id,
        "--debug",
        "--no-pub",
        "--dart-define=HYDRACAM_AUTOMATION=true",
        f"--dart-define=HYDRACAM_AUTOMATION_ROLE={role}",
        f"--dart-define=HYDRACAM_AUTOMATION_PORT={port}",
        f"--dart-define=HYDRACAM_AUTOMATION_TARGET_ID={device_id}",
        "-t",
        "lib/main.dart",
    ]
    for define in dart_defines or []:
        command.insert(-2, f"--dart-define={define}")
    if master_ip:
        command.insert(
            -2,
            f"--dart-define=HYDRACAM_AUTOMATION_MASTER_IP={master_ip}",
        )
    return command


def launch_flutter(
    device_id: str,
    log_path: Path,
    *,
    port: int = DEFAULT_PORT,
    role: str = "master",
    master_ip: str | None = None,
    dart_defines: list[str] | None = None,
) -> subprocess.Popen[str]:
    command = build_flutter_launch_command(
        device_id,
        port,
        role=role,
        master_ip=master_ip,
        dart_defines=dart_defines,
    )
    log_handle = log_path.open("w", encoding="utf-8")
    process = subprocess.Popen(
        command,
        cwd=REPO_ROOT,
        stdin=subprocess.PIPE,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
    )
    process._hydracam_log_handle = log_handle  # type: ignore[attr-defined]
    return process


def stop_flutter(process: subprocess.Popen[str] | None) -> None:
    if process is None:
        return
    if process.poll() is None and process.stdin is not None:
        process.stdin.write("q\n")
        process.stdin.flush()
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=15)
    log_handle = getattr(process, "_hydracam_log_handle", None)
    if log_handle is not None:
        log_handle.close()


def run_repro(args: argparse.Namespace) -> int:
    run_dir = (args.run_dir or REPO_ROOT / "logs" / "verification-runs" / now_slug())
    run_dir.mkdir(parents=True, exist_ok=True)

    process: subprocess.Popen[str] | None = None
    if args.launch:
        if not args.device_id:
            raise ReproError("--device-id is required with --launch")
        process = launch_flutter(
            args.device_id,
            run_dir / "flutter-run.log",
            port=args.port,
        )

    deadline = time.time() + args.timeout
    if args.bridge_url:
        bridge_url = args.bridge_url
    elif args.host == "auto":
        bridge_url = discover_bridge(
            args.port,
            args.scan_subnet,
            deadline,
            required_command="start_session",
        )
        (run_dir / "bridge-url.txt").write_text(bridge_url + "\n", encoding="utf-8")
    else:
        bridge_url = f"http://{args.host}:{args.port}"

    snapshots: dict[str, Any] = {}
    try:
        wait_for_bridge(bridge_url, deadline)
        request_json(
            bridge_url,
            "POST",
            "/settings",
            {
                "masterShouldRecord": True,
                "timerDuration": 0,
                "autoplayVideoOnMaster": False,
                "flashForVideoAnnounce": False,
                "autoUploadMaterials": True,
                "cameraLensPreference": args.lens,
                "videoCaptureProfile": args.profile,
            },
        )
        snapshots["settings"] = request_json(bridge_url, "GET", "/settings")

        session_id = f"ios-repro-{int(time.time())}"
        snapshots["start_session"] = post_command(
            bridge_url,
            "start_session",
            {"sessionId": session_id},
            deadline,
        )
        snapshots["after_start_session"] = request_json(
            bridge_url, "GET", "/session"
        )

        snapshots["take_photo"] = post_command(
            bridge_url,
            "take_photo",
            {"showCountdown": False},
            deadline,
        )
        snapshots["after_take_photo"] = request_json(bridge_url, "GET", "/session")

        snapshots["start_recording"] = post_command(
            bridge_url,
            "start_recording",
            {},
            deadline,
        )
        snapshots["after_start_recording"] = request_json(
            bridge_url, "GET", "/session"
        )

        time.sleep(args.record_seconds)
        snapshots["stop_recording"] = post_command(
            bridge_url,
            "stop_recording",
            {},
            deadline,
        )
        snapshots["after_stop_recording"] = request_json(
            bridge_url, "GET", "/session"
        )

        snapshots["logs"] = request_json(bridge_url, "GET", "/logs", timeout=20)
        write_json(run_dir / "automation-snapshots.json", snapshots)

        after_photo = snapshots["after_take_photo"]
        after_start_recording = snapshots["after_start_recording"]
        after_stop_recording = snapshots["after_stop_recording"]

        failures: list[str] = []
        if after_photo.get("photoCount", 0) < 1:
            failures.append("photoCount did not increase after take_photo")
        if not after_start_recording.get("isRecording"):
            failures.append("isRecording was not true after start_recording")
        if after_stop_recording.get("videoCount", 0) < 1:
            failures.append("videoCount did not increase after stop_recording")
        if after_stop_recording.get("isRecording"):
            failures.append("isRecording remained true after stop_recording")

        summary = {
            "bridgeUrl": bridge_url,
            "runDir": str(run_dir),
            "status": "failed" if failures else "passed",
            "failures": failures,
            "traceFilePath": snapshots["logs"].get("traceFilePath"),
        }
        write_json(run_dir / "summary.json", summary)

        if failures:
            raise ReproError("; ".join(failures))

        print(run_dir)
        return 0
    finally:
        if not args.keep_running:
            stop_flutter(process)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--host",
        help="iPad/iPhone IP or hostname for the bridge, or 'auto' to scan",
    )
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument(
        "--scan-subnet",
        default=DEFAULT_SCAN_SUBNET,
        help="IPv4 subnet to scan when --host auto is used",
    )
    parser.add_argument("--bridge-url", help="Full automation bridge URL")
    parser.add_argument("--device-id", help="Flutter device id to launch")
    parser.add_argument("--launch", action="store_true", help="Run flutter first")
    parser.add_argument(
        "--keep-running",
        action="store_true",
        help="Leave flutter run attached after the repro",
    )
    parser.add_argument(
        "--record-seconds",
        type=float,
        default=2,
        help="Seconds to record before stop_recording",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT_SECONDS,
        help="Overall wait timeout in seconds",
    )
    parser.add_argument("--run-dir", type=Path, help="Evidence output directory")
    parser.add_argument(
        "--lens",
        default="autoBack",
        help="Lens preference storage value, e.g. autoBack or ultraWide",
    )
    parser.add_argument(
        "--profile",
        default="standard1080p30",
        help="Video profile storage value, e.g. sport1080p60 or detail4k30",
    )
    args = parser.parse_args(argv)
    if not args.bridge_url and not args.host:
        parser.error("Provide --bridge-url or --host")
    return args


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        return run_repro(args)
    except ReproError as error:
        print(f"ios_capture_repro failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
