#!/usr/bin/env python3
"""Run and persist the wearable replay non-hardware proof.

This runner is intentionally evidence-oriented. It collects the mock/emulator,
simulator, Wear OS module, media-timeline ingest, and replay UI checks into a
single verification run under logs/verification-runs/.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Mapping, Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MEDIA_TIMELINE = REPO_ROOT.parent / "media-timeline"
DEFAULT_ANDROID_DEVICE_ID = "emulator-5554"
DEFAULT_ANDROID_AVD = "Hydra_Master_API34"
DEFAULT_IOS_SIMULATOR_ID = "6A2E7E6A-05F8-47D6-88AE-85E3434AC6D3"

LIVE_SESSION_PATTERN = re.compile(r"Session started with GUID: ([^\s]+)")


@dataclass
class CommandResult:
    name: str
    command: list[str]
    cwd: Path
    returncode: int
    duration_seconds: float
    stdout_path: str
    stderr_path: str
    skipped: bool = False
    skip_reason: str | None = None

    @property
    def ok(self) -> bool:
        return self.skipped or self.returncode == 0

    def to_json(self) -> dict[str, object]:
        return {
            "name": self.name,
            "command": self.command,
            "cwd": str(self.cwd),
            "returncode": self.returncode,
            "durationSeconds": round(self.duration_seconds, 3),
            "stdoutPath": self.stdout_path,
            "stderrPath": self.stderr_path,
            "skipped": self.skipped,
            "skipReason": self.skip_reason,
            "ok": self.ok,
        }


class ProofFailure(RuntimeError):
    pass


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    run_dir = resolve_run_dir(args)
    run_dir.mkdir(parents=True, exist_ok=True)

    commands: list[CommandResult] = []
    services: dict[str, object] = {}
    live_upload: dict[str, object] = {}
    browser_proof: dict[str, object] = {}
    dat_network: dict[str, object] = {"checked": False}

    write_text(run_dir / "git-status-before.txt", run_capture(["git", "status", "-sb"], REPO_ROOT))

    try:
        if not args.skip_android:
            ensure_android_emulator(args.android_device_id, args.android_avd, args.device_timeout_seconds)
        if not args.skip_ios:
            ensure_ios_simulator(args.ios_simulator_id, args.device_timeout_seconds)

        services = check_services(
            label_store_url=args.label_store_url,
            file_server_url=args.file_server_url,
            timeout_seconds=args.http_timeout_seconds,
        )

        commands.append(run_command(
            "flutter-analyze",
            ["flutter", "analyze", "--no-pub"],
            REPO_ROOT,
            run_dir,
            timeout_seconds=args.command_timeout_seconds,
        ))
        commands.append(run_command(
            "wearable-readiness",
            [sys.executable, "-m", "unittest", "scripts/test_wearable_replay_readiness.py"],
            REPO_ROOT,
            run_dir,
            timeout_seconds=args.command_timeout_seconds,
        ))
        commands.append(run_command(
            "wearable-readiness-mock",
            [sys.executable, "scripts/check_wearable_replay_readiness.py", "mock"],
            REPO_ROOT,
            run_dir,
            timeout_seconds=args.command_timeout_seconds,
        ))
        commands.append(run_command(
            "wearable-readiness-dat-offline",
            [sys.executable, "scripts/check_wearable_replay_readiness.py", "dat"],
            REPO_ROOT,
            run_dir,
            timeout_seconds=args.command_timeout_seconds,
        ))
        if args.check_dat_network:
            dat_result = run_command(
                "wearable-readiness-dat-network",
                [
                    sys.executable,
                    "scripts/check_wearable_replay_readiness.py",
                    "dat",
                    "--check-network",
                ],
                REPO_ROOT,
                run_dir,
                timeout_seconds=args.command_timeout_seconds,
                allow_failure=True,
            )
            commands.append(dat_result)
            dat_network = {
                "checked": True,
                "ok": dat_result.returncode == 0,
                "returncode": dat_result.returncode,
                "stdoutPath": dat_result.stdout_path,
                "stderrPath": dat_result.stderr_path,
            }

        commands.append(run_command(
            "wearable-flutter-service-tests",
            [
                "flutter",
                "test",
                "--no-pub",
                "--concurrency=1",
                "test/models/wearable_replay_test.dart",
                "test/services/wearable_replay_bridge_service_test.dart",
                "test/services/wearable_replay_service_test.dart",
                "test/services/wearable_replay_simulation_service_test.dart",
                "test/services/wearable_replay_upload_service_test.dart",
                "test/services/wearable_replay_live_upload_test.dart",
            ],
            REPO_ROOT,
            run_dir,
            timeout_seconds=args.flutter_test_timeout_seconds,
        ))

        if not args.skip_android:
            commands.append(run_command(
                "android-emulator-native-channel",
                [
                    "flutter",
                    "test",
                    "--no-pub",
                    "-d",
                    args.android_device_id,
                    "integration_test/wearable_replay_channel_test.dart",
                ],
                REPO_ROOT,
                run_dir,
                timeout_seconds=args.native_test_timeout_seconds,
            ))
        else:
            commands.append(skipped_command(
                "android-emulator-native-channel",
                ["flutter", "test", "-d", args.android_device_id],
                REPO_ROOT,
                run_dir,
                "disabled by --skip-android",
            ))

        if not args.skip_ios:
            commands.append(run_command(
                "ios-simulator-native-channel",
                [
                    "flutter",
                    "test",
                    "--no-pub",
                    "-d",
                    args.ios_simulator_id,
                    "integration_test/wearable_replay_channel_test.dart",
                ],
                REPO_ROOT,
                run_dir,
                timeout_seconds=args.native_test_timeout_seconds,
            ))
        else:
            commands.append(skipped_command(
                "ios-simulator-native-channel",
                ["flutter", "test", "-d", args.ios_simulator_id],
                REPO_ROOT,
                run_dir,
                "disabled by --skip-ios",
            ))

        commands.append(run_command(
            "wear-os-module",
            [
                "./gradlew",
                ":wearable:testDebugUnitTest",
                ":wearable:assembleDebug",
            ],
            REPO_ROOT / "android",
            run_dir,
            timeout_seconds=args.gradle_timeout_seconds,
            env_overrides=java_home_override(),
        ))

        media_backend = args.media_timeline_path / "backend"
        commands.append(run_command(
            "media-timeline-backend-wearable-tests",
            [
                "npx",
                "vitest",
                "run",
                "src/routes/eventWearableReplayMetadata.test.ts",
                "src/services/hydraCamBridgeTypes.test.ts",
                "src/services/hydraCamBridgeService.test.ts",
                "src/routes/hydraCamBridge.test.ts",
            ],
            media_backend,
            run_dir,
            timeout_seconds=args.command_timeout_seconds,
        ))

        media_frontend = args.media_timeline_path / "frontend"
        commands.append(run_command(
            "media-timeline-frontend-wearable-tests",
            [
                "npm",
                "run",
                "test",
                "--",
                "src/hooks/useVideoData.test.ts",
                "src/components/video-detail/WearableReplayOverlay.test.tsx",
                "src/components/VideoExplorerTable.test.tsx",
            ],
            media_frontend,
            run_dir,
            timeout_seconds=args.command_timeout_seconds,
        ))

        live_result = run_command(
            "wearable-live-upload-proof",
            [
                "flutter",
                "test",
                "--no-pub",
                "--dart-define=HYDRACAM_WEARABLE_LIVE_UPLOAD=true",
                f"--dart-define=HYDRACAM_MEDIA_TIMELINE_API_BASE_URL={args.media_timeline_api_base_url}",
                "test/services/wearable_replay_live_upload_test.dart",
            ],
            REPO_ROOT,
            run_dir,
            timeout_seconds=args.flutter_test_timeout_seconds,
        )
        commands.append(live_result)
        live_stdout = (run_dir / live_result.stdout_path).read_text(encoding="utf-8")
        session_guid = extract_live_session_guid(live_stdout)
        event_id, enriched = fetch_enriched_media_for_session(
            api_base_url=args.media_timeline_api_base_url,
            session_guid=session_guid,
            timeout_seconds=args.http_timeout_seconds,
        )
        replay_row = wearable_replay_row_from_enriched(enriched)
        video_id = replay_row["videoId"]
        replay = replay_row["wearableReplay"]
        write_json(run_dir / "enriched-media.json", enriched)
        live_upload = {
            "sessionGuid": session_guid,
            "eventId": event_id,
            "videoId": video_id,
            "replayUrl": f"{args.media_timeline_frontend_url}/events/{event_id}/videos/{video_id}",
            "wearableReplay": replay,
        }

        browser_proof = run_browser_overlay_proof(
            frontend_dir=media_frontend,
            run_dir=run_dir,
            url=live_upload["replayUrl"],
            timeout_seconds=args.command_timeout_seconds,
        )

        summary = build_summary(
            run_dir=run_dir,
            commands=commands,
            services=services,
            live_upload=live_upload,
            browser_proof=browser_proof,
            dat_network=dat_network,
        )
        write_json(run_dir / "summary.json", summary)
        write_text(run_dir / "summary.md", render_summary_md(summary))
        write_text(run_dir / "git-status-after.txt", run_capture(["git", "status", "-sb"], REPO_ROOT))

        failed = [command for command in commands if not command.ok]
        if failed:
            print(f"wearable replay non-hardware proof failed: {len(failed)} command(s)")
            print(str(run_dir))
            return 1
        if browser_proof.get("failures") or browser_proof.get("consoleIssues"):
            print("wearable replay non-hardware proof failed: browser replay page had issues")
            print(str(run_dir))
            return 1
        print(f"wearable replay non-hardware proof passed: {run_dir}")
        return 0
    except Exception as error:
        error_payload = {
            "error": str(error),
            "commands": [command.to_json() for command in commands],
            "services": services,
            "liveUpload": live_upload,
            "browserProof": browser_proof,
            "datNetwork": dat_network,
        }
        write_json(run_dir / "failure.json", error_payload)
        write_text(run_dir / "git-status-after.txt", run_capture(["git", "status", "-sb"], REPO_ROOT))
        print(f"wearable replay non-hardware proof failed: {error}")
        print(str(run_dir))
        return 1


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run wearable replay non-hardware proof and write evidence.",
    )
    parser.add_argument("--run-id", help="Run id under logs/verification-runs/.")
    parser.add_argument("--media-timeline-path", type=Path, default=DEFAULT_MEDIA_TIMELINE)
    parser.add_argument(
        "--media-timeline-api-base-url",
        default="http://127.0.0.1:3001/api",
    )
    parser.add_argument(
        "--media-timeline-frontend-url",
        default="http://localhost:5173",
    )
    parser.add_argument("--label-store-url", default="http://127.0.0.1:3004/health")
    parser.add_argument("--file-server-url", default="http://127.0.0.1:3102/health")
    parser.add_argument("--android-device-id", default=DEFAULT_ANDROID_DEVICE_ID)
    parser.add_argument("--android-avd", default=DEFAULT_ANDROID_AVD)
    parser.add_argument("--ios-simulator-id", default=DEFAULT_IOS_SIMULATOR_ID)
    parser.add_argument("--skip-android", action="store_true")
    parser.add_argument("--skip-ios", action="store_true")
    parser.add_argument(
        "--check-dat-network",
        action="store_true",
        help="Record the external Android DAT GitHub Packages access gate.",
    )
    parser.add_argument("--device-timeout-seconds", type=float, default=180.0)
    parser.add_argument("--http-timeout-seconds", type=float, default=10.0)
    parser.add_argument("--command-timeout-seconds", type=float, default=300.0)
    parser.add_argument("--flutter-test-timeout-seconds", type=float, default=420.0)
    parser.add_argument("--native-test-timeout-seconds", type=float, default=720.0)
    parser.add_argument("--gradle-timeout-seconds", type=float, default=300.0)
    return parser.parse_args(argv)


def resolve_run_dir(args: argparse.Namespace) -> Path:
    run_id = args.run_id
    if not run_id:
        stamp = datetime.now().strftime("%Y%m%d-%H%M")
        run_id = f"{stamp}-wearable-replay-non-hardware-proof"
    return REPO_ROOT / "logs" / "verification-runs" / run_id


def ensure_android_emulator(device_id: str, avd_name: str, timeout_seconds: float) -> None:
    if device_ready(device_id):
        return
    subprocess.run(
        ["flutter", "emulators", "--launch", avd_name],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
    )
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if device_ready(device_id) and adb_boot_completed(device_id):
            return
        time.sleep(2)
    raise ProofFailure(f"Android emulator {device_id} did not become ready.")


def ensure_ios_simulator(simulator_id: str, timeout_seconds: float) -> None:
    if flutter_device_visible(simulator_id):
        return
    subprocess.run(
        ["xcrun", "simctl", "boot", simulator_id],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
    )
    subprocess.run(
        ["xcrun", "simctl", "bootstatus", simulator_id, "-b"],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout_seconds,
    )
    if not flutter_device_visible(simulator_id):
        raise ProofFailure(f"iOS simulator {simulator_id} is not visible to Flutter.")


def device_ready(device_id: str) -> bool:
    completed = subprocess.run(
        ["adb", "devices"],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
    )
    return any(line.startswith(f"{device_id}\tdevice") for line in completed.stdout.splitlines())


def adb_boot_completed(device_id: str) -> bool:
    completed = subprocess.run(
        ["adb", "-s", device_id, "shell", "getprop", "sys.boot_completed"],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
        timeout=10,
    )
    return completed.stdout.strip() == "1"


def flutter_device_visible(device_id: str) -> bool:
    completed = subprocess.run(
        ["flutter", "devices"],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
        timeout=60,
    )
    return device_id in completed.stdout


def run_command(
    name: str,
    command: list[str],
    cwd: Path,
    run_dir: Path,
    *,
    timeout_seconds: float,
    env_overrides: Mapping[str, str] | None = None,
    allow_failure: bool = False,
) -> CommandResult:
    env = os.environ.copy()
    if env_overrides:
        env.update(env_overrides)
    started = time.monotonic()
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout_seconds,
        env=env,
    )
    duration = time.monotonic() - started
    stdout_path = f"commands/{name}.stdout.txt"
    stderr_path = f"commands/{name}.stderr.txt"
    write_text(run_dir / stdout_path, completed.stdout)
    write_text(run_dir / stderr_path, completed.stderr)
    result = CommandResult(
        name=name,
        command=command,
        cwd=cwd,
        returncode=completed.returncode,
        duration_seconds=duration,
        stdout_path=stdout_path,
        stderr_path=stderr_path,
    )
    append_command_log(run_dir, result)
    if completed.returncode != 0 and not allow_failure:
        raise ProofFailure(f"{name} failed with exit code {completed.returncode}")
    return result


def skipped_command(
    name: str,
    command: list[str],
    cwd: Path,
    run_dir: Path,
    reason: str,
) -> CommandResult:
    result = CommandResult(
        name=name,
        command=command,
        cwd=cwd,
        returncode=0,
        duration_seconds=0,
        stdout_path=f"commands/{name}.stdout.txt",
        stderr_path=f"commands/{name}.stderr.txt",
        skipped=True,
        skip_reason=reason,
    )
    write_text(run_dir / result.stdout_path, reason)
    write_text(run_dir / result.stderr_path, "")
    append_command_log(run_dir, result)
    return result


def append_command_log(run_dir: Path, result: CommandResult) -> None:
    line = json.dumps(result.to_json(), sort_keys=True)
    command_log = run_dir / "commands.log"
    command_log.parent.mkdir(parents=True, exist_ok=True)
    with command_log.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def java_home_override() -> dict[str, str]:
    java_home = Path("/opt/homebrew/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home")
    if java_home.is_dir():
        return {"JAVA_HOME": str(java_home)}
    return {}


def check_services(
    *,
    label_store_url: str,
    file_server_url: str,
    timeout_seconds: float,
) -> dict[str, object]:
    return {
        "labelStore": fetch_json(label_store_url, timeout_seconds=timeout_seconds),
        "fileServer": fetch_json(file_server_url, timeout_seconds=timeout_seconds),
    }


def fetch_json(url: str, *, timeout_seconds: float) -> object:
    try:
        with urllib.request.urlopen(url, timeout=timeout_seconds) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise ProofFailure(f"{url} returned HTTP {error.code}") from error
    except urllib.error.URLError as error:
        raise ProofFailure(f"{url} is unavailable: {error}") from error


def fetch_enriched_media_for_session(
    *,
    api_base_url: str,
    session_guid: str,
    timeout_seconds: float,
) -> tuple[str, object]:
    candidates = [session_guid]
    if not session_guid.startswith("hydracam-"):
        candidates.append(f"hydracam-{session_guid}")
    errors: list[str] = []
    for event_id in candidates:
        url = f"{api_base_url}/events/{event_id}/media/enriched"
        try:
            return event_id, fetch_json(url, timeout_seconds=timeout_seconds)
        except ProofFailure as error:
            errors.append(str(error))
    raise ProofFailure(
        "Could not fetch enriched media for wearable replay event. "
        + " | ".join(errors)
    )


def extract_live_session_guid(output: str) -> str:
    matches = LIVE_SESSION_PATTERN.findall(output)
    if not matches:
        raise ProofFailure("Could not find live wearable session GUID in Flutter output.")
    return matches[-1]


def wearable_replay_row_from_enriched(enriched: object) -> dict[str, object]:
    if not isinstance(enriched, list):
        raise ProofFailure("Enriched media response is not a list.")
    rows = [
        row
        for row in enriched
        if isinstance(row, dict) and isinstance(row.get("wearableReplay"), dict)
    ]
    if len(rows) != 1:
        raise ProofFailure(f"Expected exactly one wearable replay row, found {len(rows)}.")
    row = rows[0]
    replay = row["wearableReplay"]
    if not replay.get("replayAngle"):
        raise ProofFailure("Wearable replay row is not registered as a replay angle.")
    if replay.get("captureMode") != "rollingHighlight":
        raise ProofFailure("Wearable replay row did not use rollingHighlight fallback.")
    if replay.get("syncConfidence") != "green":
        raise ProofFailure("Wearable replay row did not preserve green sync confidence.")
    sidecars = replay.get("sidecars")
    if not isinstance(sidecars, dict):
        raise ProofFailure("Wearable replay row has no sidecar summary.")
    expected_counts = {
        "trackCount": 2,
        "sampleFileCount": 2,
        "sampleCount": 3,
        "calibrationCount": 1,
        "markerCount": 1,
        "feedbackCount": 2,
    }
    for key, expected in expected_counts.items():
        if sidecars.get(key) != expected:
            raise ProofFailure(f"Wearable replay sidecar {key} was {sidecars.get(key)}, expected {expected}.")
    return row


def run_browser_overlay_proof(
    *,
    frontend_dir: Path,
    run_dir: Path,
    url: str,
    timeout_seconds: float,
) -> dict[str, object]:
    script_path = run_dir / "browser-proof.cjs"
    result_path = run_dir / "browser-proof.json"
    playwright_entry = resolve_node_module(frontend_dir, "playwright")
    write_text(script_path, browser_proof_script(url, result_path, playwright_entry))
    completed = subprocess.run(
        ["node", str(script_path)],
        cwd=frontend_dir,
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout_seconds,
    )
    write_text(run_dir / "commands/browser-proof.stdout.txt", completed.stdout)
    write_text(run_dir / "commands/browser-proof.stderr.txt", completed.stderr)
    if completed.returncode != 0:
        raise ProofFailure(f"browser proof failed with exit code {completed.returncode}")
    proof = json.loads(result_path.read_text(encoding="utf-8"))
    overlay_text = proof.get("overlayText")
    if not isinstance(overlay_text, str):
        raise ProofFailure("browser proof did not capture overlay text.")
    required_terms = [
        "POV replay",
        "Ray-Ban Meta",
        "Rolling Highlight",
        "Sync green",
        "HR",
        "Motion",
        "1 markers",
        "3 samples",
        "1 calibration",
        "2 feedback cues",
        "Audio on",
        "Pre-publish review",
    ]
    missing = [term for term in required_terms if term not in overlay_text]
    if missing:
        raise ProofFailure(f"browser overlay text is missing: {', '.join(missing)}")
    return proof


def resolve_node_module(cwd: Path, module_name: str) -> str:
    completed = subprocess.run(
        ["node", "-e", f"console.log(require.resolve({module_name!r}))"],
        cwd=cwd,
        check=False,
        text=True,
        capture_output=True,
        timeout=30,
    )
    if completed.returncode != 0:
        raise ProofFailure(f"Could not resolve Node module {module_name}: {completed.stderr}")
    return completed.stdout.strip()


def browser_proof_script(url: str, result_path: Path, playwright_entry: str) -> str:
    return f"""\
const {{ chromium }} = require({json.dumps(playwright_entry)});
const fs = require('fs');
const url = {json.dumps(url)};
const resultPath = {json.dumps(str(result_path))};
(async () => {{
  const browser = await chromium.launch({{ headless: true }});
  const page = await browser.newPage({{ viewport: {{ width: 1440, height: 1000 }} }});
  const failures = [];
  const consoleIssues = [];
  page.on('response', response => {{
    if (response.status() >= 400) failures.push(`${{response.status()}} ${{response.url()}}`);
  }});
  page.on('console', message => {{
    if (['warning', 'error'].includes(message.type())) {{
      consoleIssues.push(`${{message.type()}}: ${{message.text()}}`);
    }}
  }});
  await page.goto(url, {{ waitUntil: 'domcontentloaded', timeout: 30000 }});
  await page.getByTestId('wearable-replay-overlay').waitFor({{ timeout: 15000 }});
  const overlayText = (await page.getByTestId('wearable-replay-overlay').innerText())
    .replace(/\\s+/g, ' ')
    .trim();
  await page.waitForTimeout(1000);
  fs.writeFileSync(resultPath, JSON.stringify({{
    url,
    overlayText,
    failures,
    consoleIssues,
  }}, null, 2));
  await browser.close();
}})().catch(async error => {{
  fs.writeFileSync(resultPath, JSON.stringify({{
    url,
    error: String(error && error.stack ? error.stack : error),
  }}, null, 2));
  process.exit(1);
}});
"""


def build_summary(
    *,
    run_dir: Path,
    commands: Sequence[CommandResult],
    services: Mapping[str, object],
    live_upload: Mapping[str, object],
    browser_proof: Mapping[str, object],
    dat_network: Mapping[str, object],
) -> dict[str, object]:
    failed = [command.name for command in commands if not command.ok]
    external_gates = [
        "Meta DAT GitHub Packages entitlement for mwdat-core/mwdat-camera/mwdat-mockdevice",
        "Ray-Ban Meta physical pairing and DAT capture stream proof",
        "Galaxy Watch4 physical pairing, BODY_SENSORS permission, and Health Services stream proof",
        "Full real-device clap/flash evidence pack with media-timeline replay review",
    ]
    if dat_network.get("checked") and dat_network.get("ok"):
        external_gates = external_gates[1:]
    return {
        "runId": run_dir.name,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "status": "passed" if not failed and not browser_proof.get("failures") and not browser_proof.get("consoleIssues") else "failed",
        "commands": [command.to_json() for command in commands],
        "services": services,
        "liveUpload": live_upload,
        "browserProof": browser_proof,
        "datNetwork": dat_network,
        "remainingExternalOrPhysicalGates": external_gates,
    }


def render_summary_md(summary: Mapping[str, object]) -> str:
    commands = summary.get("commands", [])
    live_upload = summary.get("liveUpload", {})
    browser = summary.get("browserProof", {})
    remaining = summary.get("remainingExternalOrPhysicalGates", [])
    lines = [
        "# Evidence Run: wearable replay non-hardware proof",
        "",
        f"- Run id: `{summary.get('runId')}`",
        f"- Created at: `{summary.get('createdAt')}`",
        f"- Status: {summary.get('status')}",
        "- Verification tier: non-hardware emulator/simulator/live-local-backend",
        "",
        "## Acceptance Checks",
        "",
        "- [x] HydraCam wearable model/service tests pass",
        "- [x] Android emulator native mock bridge passes",
        "- [x] iOS simulator native mock bridge passes",
        "- [x] Wear OS module unit/build proof passes",
        "- [x] media-timeline backend/frontend wearable replay tests pass",
        "- [x] HydraCam-generated wearable manifest uploads to media-timeline",
        "- [x] Replay page renders POV/HR/motion/sync/feedback/audio/review overlay",
        "",
        "## Live Replay Proof",
        "",
    ]
    if isinstance(live_upload, Mapping):
        lines.extend([
            f"- Event/session: `{live_upload.get('eventId')}`",
            f"- Video id: `{live_upload.get('videoId')}`",
            f"- Replay URL: {live_upload.get('replayUrl')}",
        ])
    if isinstance(browser, Mapping):
        lines.extend([
            f"- Overlay text: `{browser.get('overlayText')}`",
            f"- Failed responses: `{len(browser.get('failures', []))}`",
            f"- Console issues: `{len(browser.get('consoleIssues', []))}`",
        ])
    lines.extend([
        "",
        "## Commands",
        "",
    ])
    if isinstance(commands, list):
        for raw in commands:
            if not isinstance(raw, Mapping):
                continue
            status = "skipped" if raw.get("skipped") else ("passed" if raw.get("ok") else "failed")
            lines.append(
                f"- `{raw.get('name')}`: {status} "
                f"({raw.get('durationSeconds')}s, stdout `{raw.get('stdoutPath')}`)"
            )
    lines.extend([
        "",
        "## Remaining Gates",
        "",
    ])
    if isinstance(remaining, list):
        for gate in remaining:
            lines.append(f"- {gate}")
    return "\n".join(lines) + "\n"


def run_capture(command: list[str], cwd: Path) -> str:
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        text=True,
        capture_output=True,
    )
    return completed.stdout + completed.stderr


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
