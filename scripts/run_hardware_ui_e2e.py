#!/usr/bin/env python3
"""Run HydraCam UI smoke checks directly on connected Android hardware.

The script builds the current checkout with the automation bridge enabled,
installs it on selected ADB devices, launches app routes through Android
intent extras, captures in-app screenshots through the automation bridge, and
fails if Flutter reports a visible overflow.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
PACKAGE_NAME = "com.amaia23.hydracam"
MAIN_ACTIVITY = f"{PACKAGE_NAME}/.MainActivity"
REMOTE_AUTOMATION_PORT = 4762
DEFAULT_APK = REPO_ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"
DEFAULT_ROUTES = ("setup", "standby")
DEFAULT_SCROLL_CHECK_ROUTES = ("setup",)
OVERFLOW_MARKERS = (
    "A RenderFlex overflowed",
    "RenderFlex overflowed",
    "overflowed by",
)
ANDROID_PERMISSIONS = (
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VIDEO",
)


class HardwareUiE2EError(RuntimeError):
    pass


def now_slug() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M-hardware-ui-e2e")


def run_command(
    command: Sequence[str],
    *,
    timeout: float,
    check: bool = True,
    capture_output: bool = False,
    text: bool = True,
) -> subprocess.CompletedProcess[Any]:
    print("+ " + " ".join(command), flush=True)
    return subprocess.run(
        list(command),
        cwd=REPO_ROOT,
        check=check,
        timeout=timeout,
        capture_output=capture_output,
        text=text,
    )


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
        raise HardwareUiE2EError(
            f"{method} {path} failed: HTTP {error.code}: {details}"
        ) from error
    except OSError as error:
        raise HardwareUiE2EError(f"{method} {path} failed: {error}") from error
    if not data:
        return {}
    decoded = json.loads(data)
    if not isinstance(decoded, dict):
        raise HardwareUiE2EError(f"{method} {path} returned non-object JSON")
    return decoded


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def discover_adb_devices(*, include_emulators: bool) -> list[dict[str, str]]:
    result = run_command(
        ["adb", "devices", "-l"],
        timeout=15,
        capture_output=True,
    )
    devices: list[dict[str, str]] = []
    for line in result.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 2 or parts[1] != "device":
            continue
        serial = parts[0]
        if serial.startswith("emulator-") and not include_emulators:
            continue
        descriptor = " ".join(parts[2:])
        devices.append({"serial": serial, "descriptor": descriptor})
    return devices


def select_devices(
    discovered: Sequence[dict[str, str]],
    requested_serials: Sequence[str],
) -> list[dict[str, str]]:
    if not requested_serials:
        return list(discovered)
    by_serial = {device["serial"]: device for device in discovered}
    missing = [serial for serial in requested_serials if serial not in by_serial]
    if missing:
        raise HardwareUiE2EError(
            "Requested ADB device(s) not connected: " + ", ".join(missing)
        )
    return [by_serial[serial] for serial in requested_serials]


def build_apk(args: argparse.Namespace) -> Path:
    apk = Path(args.apk)
    if args.skip_build:
        if not apk.exists():
            raise HardwareUiE2EError(f"APK does not exist: {apk}")
        return apk
    run_command(
        [
            "flutter",
            "build",
            "apk",
            "--debug",
            "--dart-define=HYDRACAM_AUTOMATION=true",
        ],
        timeout=args.build_timeout,
    )
    if not apk.exists():
        raise HardwareUiE2EError(f"Flutter build did not produce APK: {apk}")
    return apk


def prepare_device(serial: str, apk: Path, *, local_port: int, skip_install: bool) -> None:
    run_command(["adb", "-s", serial, "forward", "--remove-all"], timeout=15, check=False)
    if not skip_install:
        run_command(["adb", "-s", serial, "install", "-r", str(apk)], timeout=180)
    for permission in ANDROID_PERMISSIONS:
        try:
            run_command(
                ["adb", "-s", serial, "shell", "pm", "grant", PACKAGE_NAME, permission],
                timeout=8,
                check=False,
            )
        except subprocess.TimeoutExpired:
            print(f"warning: timed out granting {permission} on {serial}", flush=True)
    run_command(
        [
            "adb",
            "-s",
            serial,
            "forward",
            f"tcp:{local_port}",
            f"tcp:{REMOTE_AUTOMATION_PORT}",
        ],
        timeout=15,
    )


def launch_route(serial: str, route: str) -> None:
    run_command(["adb", "-s", serial, "logcat", "-c"], timeout=15, check=False)
    try:
        run_command(
            ["adb", "-s", serial, "shell", "am", "force-stop", PACKAGE_NAME],
            timeout=8,
            check=False,
        )
    except subprocess.TimeoutExpired:
        print(f"warning: timed out force-stopping {PACKAGE_NAME} on {serial}", flush=True)
    run_command(
        [
            "adb",
            "-s",
            serial,
            "shell",
            "am",
            "start",
            "-n",
            MAIN_ACTIVITY,
            "--es",
            "role",
            route,
            "--es",
            "automationTargetId",
            serial,
        ],
        timeout=20,
    )


def wait_for_bridge(
    serial: str,
    bridge_url: str,
    *,
    timeout: float,
) -> dict[str, Any]:
    deadline = time.time() + timeout
    last_payload: dict[str, Any] = {}
    while time.time() < deadline:
        try:
            payload = request_json(bridge_url, "GET", "/healthz", timeout=3)
            last_payload = payload
            commands = payload.get("commands", [])
            if (
                payload.get("status") == "ok"
                and payload.get("automationTargetId") == serial
                and isinstance(commands, list)
                and "capture_screenshot" in commands
            ):
                return payload
        except HardwareUiE2EError:
            pass
        time.sleep(1)
    raise HardwareUiE2EError(
        f"Automation bridge did not become healthy for {serial}: {last_payload}"
    )


def pull_screenshot(
    serial: str,
    remote_path: str,
    destination: Path,
    *,
    timeout: float,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = ["adb", "-s", serial, "exec-out", "run-as", PACKAGE_NAME, "cat", remote_path]
    print("+ " + " ".join(command) + f" > {destination}", flush=True)
    with destination.open("wb") as handle:
        result = subprocess.run(
            command,
            cwd=REPO_ROOT,
            stdout=handle,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace")
        raise HardwareUiE2EError(f"Failed to pull screenshot from {serial}: {stderr}")
    if destination.stat().st_size == 0:
        raise HardwareUiE2EError(f"Pulled empty screenshot from {serial}: {destination}")


def collect_logcat(serial: str, path: Path, *, tail_lines: int) -> str:
    result = run_command(
        ["adb", "-s", serial, "logcat", "-d", "-t", str(tail_lines)],
        timeout=30,
        capture_output=True,
        check=False,
    )
    path.write_text(result.stdout, encoding="utf-8")
    return result.stdout


def get_screen_size(serial: str) -> tuple[int, int] | None:
    result = run_command(
        ["adb", "-s", serial, "shell", "wm", "size"],
        timeout=10,
        capture_output=True,
        check=False,
    )
    matches = re.findall(r"(\d+)x(\d+)", result.stdout)
    if not matches:
        return None
    width, height = matches[-1]
    return int(width), int(height)


def oriented_screen_size(
    serial: str,
    screenshot_result: dict[str, Any],
) -> tuple[int, int] | None:
    screen_size = get_screen_size(serial)
    if screen_size is None:
        return None
    width, height = screen_size
    viewport_width = screenshot_result.get("width")
    viewport_height = screenshot_result.get("height")
    if isinstance(viewport_width, int) and isinstance(viewport_height, int):
        viewport_is_landscape = viewport_width > viewport_height
        screen_is_landscape = width > height
        if viewport_is_landscape != screen_is_landscape:
            width, height = height, width
    return width, height


def swipe_to_bottom(
    serial: str,
    screenshot_result: dict[str, Any],
) -> dict[str, Any]:
    screen_size = oriented_screen_size(serial, screenshot_result)
    if screen_size is None:
        width, height = 1000, 1800
    else:
        width, height = screen_size
    x = width // 2
    start_y = int(height * 0.78)
    end_y = int(height * 0.22)
    duration_ms = 450
    run_command(
        [
            "adb",
            "-s",
            serial,
            "shell",
            "input",
            "swipe",
            str(x),
            str(start_y),
            str(x),
            str(end_y),
            str(duration_ms),
        ],
        timeout=15,
        check=False,
    )
    return {
        "orientedScreenSize": None
        if screen_size is None
        else {"width": screen_size[0], "height": screen_size[1]},
        "swipe": {
            "x": x,
            "startY": start_y,
            "endY": end_y,
            "durationMs": duration_ms,
        },
    }


def route_label(route: str) -> str:
    return {
        "setup": "Prepare Camera",
        "standby": "Waiting for role assignment",
    }.get(route, route)


def overflow_markers_found(text: str) -> list[str]:
    return [marker for marker in OVERFLOW_MARKERS if marker in text]


def run_route_check(
    serial: str,
    route: str,
    *,
    bridge_url: str,
    run_dir: Path,
    settle_seconds: float,
    timeout: float,
    logcat_tail_lines: int,
    scroll_check_routes: set[str],
) -> dict[str, Any]:
    device_dir = run_dir / "device-logs" / serial
    screenshot_path = run_dir / "screenshots" / f"{serial}-{route}.png"
    scroll_screenshot_path = (
        run_dir / "screenshots" / f"{serial}-{route}-after-scroll.png"
    )
    device_dir.mkdir(parents=True, exist_ok=True)

    result: dict[str, Any] = {
        "serial": serial,
        "route": route,
        "label": route_label(route),
        "bridgeUrl": bridge_url,
        "status": "started",
        "failures": [],
    }

    try:
        launch_route(serial, route)
        health = wait_for_bridge(serial, bridge_url, timeout=timeout)
        result["health"] = health
        time.sleep(settle_seconds)
        screenshot_response = request_json(
            bridge_url,
            "POST",
            "/commands/capture_screenshot",
            {
                "name": f"{serial}-{route}",
                "pixelRatio": 1,
            },
            timeout=timeout,
        )
        result["screenshotResponse"] = screenshot_response
        screenshot_result = screenshot_response.get("result", {})
        if not isinstance(screenshot_result, dict):
            raise HardwareUiE2EError("capture_screenshot returned invalid result")
        remote_path = screenshot_result.get("filePath")
        if not isinstance(remote_path, str) or not remote_path:
            raise HardwareUiE2EError("capture_screenshot did not return filePath")
        pull_screenshot(
            serial,
            remote_path,
            screenshot_path,
            timeout=timeout,
        )
        result["screenshot"] = str(screenshot_path.relative_to(run_dir))
        result["screenshotBytes"] = screenshot_path.stat().st_size

        if route in scroll_check_routes:
            scroll_check: dict[str, Any] = swipe_to_bottom(
                serial,
                screenshot_result,
            )
            time.sleep(settle_seconds)
            scroll_screenshot_response = request_json(
                bridge_url,
                "POST",
                "/commands/capture_screenshot",
                {
                    "name": f"{serial}-{route}-after-scroll",
                    "pixelRatio": 1,
                },
                timeout=timeout,
            )
            scroll_screenshot_result = scroll_screenshot_response.get("result", {})
            if not isinstance(scroll_screenshot_result, dict):
                raise HardwareUiE2EError(
                    "post-scroll capture_screenshot returned invalid result"
                )
            scroll_remote_path = scroll_screenshot_result.get("filePath")
            if not isinstance(scroll_remote_path, str) or not scroll_remote_path:
                raise HardwareUiE2EError(
                    "post-scroll capture_screenshot did not return filePath"
                )
            pull_screenshot(
                serial,
                scroll_remote_path,
                scroll_screenshot_path,
                timeout=timeout,
            )
            scroll_check.update(
                {
                    "screenshot": str(scroll_screenshot_path.relative_to(run_dir)),
                    "screenshotBytes": scroll_screenshot_path.stat().st_size,
                    "screenshotResponse": scroll_screenshot_response,
                }
            )
            result["scrollCheck"] = scroll_check

        logs = request_json(bridge_url, "GET", "/logs", timeout=timeout)
        write_json(device_dir / f"{route}-bridge-logs.json", logs)
        logcat = collect_logcat(
            serial,
            device_dir / f"{route}-logcat.txt",
            tail_lines=logcat_tail_lines,
        )
        persisted_logs = json.dumps(logs)
        markers = sorted(
            set(overflow_markers_found(logcat) + overflow_markers_found(persisted_logs))
        )
        if markers:
            result["failures"].append(
                "Flutter overflow marker(s) found: " + ", ".join(markers)
            )
    except Exception as error:
        result["failures"].append(str(error))

    result["status"] = "passed" if not result["failures"] else "failed"
    write_json(device_dir / f"{route}-result.json", result)
    return result


def write_summary(run_dir: Path, summary: dict[str, Any]) -> None:
    write_json(run_dir / "summary.json", summary)
    lines = [
        "# Hardware UI E2E",
        "",
        f"- Status: `{summary['status']}`",
        f"- Started at: `{summary['startedAt']}`",
        f"- Finished at: `{summary['finishedAt']}`",
        f"- APK: `{summary['apk']}`",
        "",
        "## Devices",
        "",
    ]
    for device in summary["devices"]:
        lines.append(f"- `{device['serial']}` {device.get('descriptor', '')}".rstrip())
    lines.extend(["", "## Routes", ""])
    for result in summary["routeResults"]:
        lines.append(
            f"- `{result['serial']}` `{result['route']}`: `{result['status']}`"
        )
        if result.get("screenshot"):
            lines.append(f"  - Screenshot: `{result['screenshot']}`")
        scroll_check = result.get("scrollCheck")
        if isinstance(scroll_check, dict) and scroll_check.get("screenshot"):
            lines.append(f"  - After-scroll screenshot: `{scroll_check['screenshot']}`")
        for failure in result.get("failures", []):
            lines.append(f"  - Failure: {failure}")
    (run_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_hardware_ui_e2e(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir or REPO_ROOT / "logs" / "verification-runs" / now_slug())
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "screenshots").mkdir(exist_ok=True)
    (run_dir / "device-logs").mkdir(exist_ok=True)

    devices = select_devices(
        discover_adb_devices(include_emulators=args.include_emulators),
        args.device,
    )
    if not devices:
        raise HardwareUiE2EError("No connected Android hardware devices selected")

    apk = build_apk(args)
    started_at = dt.datetime.now().isoformat()
    route_results: list[dict[str, Any]] = []

    for index, device in enumerate(devices):
        serial = device["serial"]
        local_port = args.port_base + index
        bridge_url = f"http://127.0.0.1:{local_port}"
        device["localPort"] = local_port
        device["bridgeUrl"] = bridge_url
        try:
            prepare_device(
                serial,
                apk,
                local_port=local_port,
                skip_install=args.skip_install,
            )
        except Exception as error:
            route_results.append(
                {
                    "serial": serial,
                    "route": "prepare_device",
                    "status": "failed",
                    "failures": [str(error)],
                }
            )
            continue
        for route in args.route:
            route_results.append(
                run_route_check(
                    serial,
                    route,
                    bridge_url=bridge_url,
                    run_dir=run_dir,
                    settle_seconds=args.settle_seconds,
                    timeout=args.timeout,
                    logcat_tail_lines=args.logcat_tail_lines,
                    scroll_check_routes=set(args.scroll_check_route),
                )
            )

    status = "passed" if all(result["status"] == "passed" for result in route_results) else "failed"
    summary = {
        "status": status,
        "startedAt": started_at,
        "finishedAt": dt.datetime.now().isoformat(),
        "apk": str(apk),
        "devices": devices,
        "routes": list(args.route),
        "scrollCheckRoutes": list(args.scroll_check_route),
        "routeResults": route_results,
    }
    write_summary(run_dir, summary)
    print(run_dir)
    return 0 if status == "passed" else 1


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run HydraCam UI e2e checks on connected Android hardware.",
    )
    parser.add_argument(
        "--device",
        action="append",
        default=[],
        help="ADB serial to include. Repeat to select multiple devices.",
    )
    parser.add_argument(
        "--route",
        action="append",
        choices=DEFAULT_ROUTES,
        default=[],
        help="Automation route to launch. Defaults to setup and standby.",
    )
    parser.add_argument(
        "--scroll-check-route",
        action="append",
        choices=DEFAULT_ROUTES,
        default=[],
        help=(
            "Route to swipe and capture again after the first screenshot. "
            "Defaults to setup."
        ),
    )
    parser.add_argument(
        "--no-scroll-checks",
        action="store_true",
        help="Disable route scroll/screenshot checks.",
    )
    parser.add_argument(
        "--run-dir",
        "--output-dir",
        type=Path,
        dest="run_dir",
        help="Evidence output directory.",
    )
    parser.add_argument("--apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--skip-install", action="store_true")
    parser.add_argument("--include-emulators", action="store_true")
    parser.add_argument("--port-base", type=int, default=6700)
    parser.add_argument("--timeout", type=float, default=45)
    parser.add_argument("--build-timeout", type=float, default=300)
    parser.add_argument("--settle-seconds", type=float, default=2)
    parser.add_argument("--logcat-tail-lines", type=int, default=800)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    if not args.route:
        args.route = list(DEFAULT_ROUTES)
    if args.no_scroll_checks:
        args.scroll_check_route = []
    elif not args.scroll_check_route:
        args.scroll_check_route = list(DEFAULT_SCROLL_CHECK_ROUTES)
    try:
        return run_hardware_ui_e2e(args)
    except HardwareUiE2EError as error:
        print(f"hardware ui e2e failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
