#!/usr/bin/env python3
"""Create and validate HydraCam evidence-first verification packs."""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ROOT = REPO_ROOT / "logs" / "verification-runs"
SCHEMA_VERSION = 1
TIERS = {
    "A": "real-hardware",
    "B": "emulator-simulator-e2e",
    "C": "multi-device-emulated-cluster",
    "D": "integration-unit-tests",
}
EVIDENCE_DIRS = ("screenshots", "video", "device-logs")


def evidence_root() -> Path:
    override = os.environ.get("HYDRACAM_EVIDENCE_ROOT")
    return Path(override).expanduser().resolve() if override else DEFAULT_ROOT


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value.lower()).strip("-")
    return slug or "verification-run"


def now_stamp() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M")


def run_git_status() -> str:
    completed = subprocess.run(
        ["git", "status", "-sb"],
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
    )
    output = completed.stdout
    if completed.stderr:
        output += "\n[stderr]\n" + completed.stderr
    return output


def unique_run_dir(root: Path, stamp: str, slug: str) -> Path:
    candidate = root / f"{stamp}-{slug}"
    suffix = 1
    while candidate.exists():
        candidate = root / f"{stamp}-{slug}-{suffix}"
        suffix += 1
    return candidate


def load_artifacts(run_dir: Path) -> dict[str, Any]:
    path = run_dir / "artifacts.json"
    if not path.exists():
        raise SystemExit(f"Missing artifacts.json in {run_dir}")
    return json.loads(path.read_text(encoding="utf-8"))


def write_artifacts(run_dir: Path, artifacts: dict[str, Any]) -> None:
    (run_dir / "artifacts.json").write_text(
        json.dumps(artifacts, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def relative_evidence_files(run_dir: Path) -> list[str]:
    evidence_files: list[str] = []
    for directory_name in EVIDENCE_DIRS:
        directory = run_dir / directory_name
        if not directory.exists():
            continue
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                evidence_files.append(path.relative_to(run_dir).as_posix())
    return evidence_files


def append_commands_log(run_dir: Path, text: str) -> None:
    with (run_dir / "commands.log").open("a", encoding="utf-8") as handle:
        handle.write(text)
        if not text.endswith("\n"):
            handle.write("\n")


@contextlib.contextmanager
def evidence_pack_lock(run_dir: Path):
    lock_path = run_dir / ".evidence-pack.lock"
    with lock_path.open("w", encoding="utf-8") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def start_command(args: argparse.Namespace) -> int:
    tier = args.tier.upper()
    if tier not in TIERS:
        raise SystemExit(f"Unknown tier {args.tier}. Use one of: {', '.join(TIERS)}")

    slug = slugify(args.slug or args.item)
    run_dir = unique_run_dir(evidence_root(), args.timestamp or now_stamp(), slug)
    run_dir.mkdir(parents=True)
    for directory_name in EVIDENCE_DIRS:
        (run_dir / directory_name).mkdir()

    acceptance_checks = args.acceptance or []
    if not acceptance_checks:
        raise SystemExit("At least one --acceptance check is required")

    (run_dir / "git-status-before.txt").write_text(
        run_git_status(),
        encoding="utf-8",
    )
    (run_dir / "commands.log").write_text(
        "# HydraCam evidence run command log\n",
        encoding="utf-8",
    )

    summary = [
        f"# Evidence Run: {args.item}",
        "",
        f"- Source: {args.source}",
        f"- Slug: `{slug}`",
        f"- Verification tier: {tier} ({TIERS[tier]})",
        "- Status: prepared",
        "",
        "## Acceptance Checks",
        "",
    ]
    summary.extend(f"- [ ] {check}" for check in acceptance_checks)
    summary.extend(
        [
            "",
            "## Device Matrix",
            "",
            "- Record device model, OS/runtime, serial/UDID, and role here.",
            "",
            "## Evidence",
            "",
            "- Add screenshots, video, logs, and command notes here.",
            "",
            "## Result",
            "",
            "- Final disposition: pending",
        ]
    )
    (run_dir / "summary.md").write_text("\n".join(summary) + "\n", encoding="utf-8")

    artifacts = {
        "schemaVersion": SCHEMA_VERSION,
        "item": {
            "title": args.item,
            "slug": slug,
            "source": args.source,
        },
        "verificationTier": tier,
        "verificationTierName": TIERS[tier],
        "requiresScreenshots": args.require_screenshots or tier in {"A", "B", "C"},
        "requiresVideo": args.require_video or tier in {"A", "B", "C"},
        "requiresDeviceLogs": args.require_device_logs or tier in {"A", "B", "C"},
        "acceptanceChecks": acceptance_checks,
        "devices": [],
        "commands": [],
        "evidenceFiles": [],
        "status": "prepared",
        "notes": [],
    }
    write_artifacts(run_dir, artifacts)
    print(run_dir)
    return 0


def run_command(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        raise SystemExit("Command is required after --")

    with evidence_pack_lock(run_dir):
        artifacts = load_artifacts(run_dir)
        started_at = dt.datetime.now(dt.timezone.utc).isoformat()
        append_commands_log(run_dir, f"\n$ {' '.join(command)}\n")
        completed = subprocess.run(
            command,
            cwd=REPO_ROOT,
            check=False,
            text=True,
            capture_output=True,
        )
        if completed.stdout:
            append_commands_log(run_dir, completed.stdout)
        if completed.stderr:
            append_commands_log(run_dir, "\n[stderr]\n" + completed.stderr)
        append_commands_log(run_dir, f"[exit-code] {completed.returncode}\n")

        artifacts.setdefault("commands", []).append(
            {
                "command": command,
                "startedAt": started_at,
                "returnCode": completed.returncode,
            }
        )
        write_artifacts(run_dir, artifacts)
    return completed.returncode


def finalize_command(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    with evidence_pack_lock(run_dir):
        artifacts = load_artifacts(run_dir)
        (run_dir / "git-status-after.txt").write_text(
            run_git_status(),
            encoding="utf-8",
        )
        artifacts["status"] = args.status
        artifacts["evidenceFiles"] = relative_evidence_files(run_dir)
        if args.note:
            artifacts.setdefault("notes", []).extend(args.note)
        write_artifacts(run_dir, artifacts)
    print(run_dir)
    return 0


def add_device_command(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    with evidence_pack_lock(run_dir):
        artifacts = load_artifacts(run_dir)
        artifacts.setdefault("devices", []).append(
            {
                "name": args.name,
                "kind": args.kind,
                "identifier": args.identifier,
                "role": args.role,
                "os": args.os,
                "notes": args.note or [],
            }
        )
        write_artifacts(run_dir, artifacts)
    print(run_dir)
    return 0


def dir_has_file(run_dir: Path, name: str) -> bool:
    directory = run_dir / name
    return directory.exists() and any(path.is_file() for path in directory.rglob("*"))


def check_command(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    artifacts = load_artifacts(run_dir)
    errors: list[str] = []

    required_files = (
        "summary.md",
        "commands.log",
        "git-status-before.txt",
        "git-status-after.txt",
        "artifacts.json",
    )
    for file_name in required_files:
        if not (run_dir / file_name).is_file():
            errors.append(f"Missing {file_name}")

    commands_log = run_dir / "commands.log"
    if commands_log.exists() and commands_log.stat().st_size <= len(
        "# HydraCam evidence run command log\n"
    ):
        errors.append("commands.log has no recorded command output")

    if not artifacts.get("acceptanceChecks"):
        errors.append("artifacts.json must include at least one acceptance check")

    if (
        artifacts.get("verificationTier") in {"A", "B", "C"}
        and not artifacts.get("devices")
    ):
        errors.append("Tier A/B/C evidence must declare at least one device")

    if artifacts.get("requiresScreenshots") and not dir_has_file(run_dir, "screenshots"):
        errors.append("screenshots/ is required but has no files")
    if artifacts.get("requiresVideo") and not dir_has_file(run_dir, "video"):
        errors.append("video/ is required but has no files")
    if artifacts.get("requiresDeviceLogs") and not dir_has_file(run_dir, "device-logs"):
        errors.append("device-logs/ is required but has no files")

    if artifacts.get("status") not in {"passed", "failed", "blocked", "partial"}:
        errors.append("status must be passed, failed, blocked, or partial")

    if errors:
        for error in errors:
            print(f"[evidence-pack] {error}", file=sys.stderr)
        return 1

    print(f"Evidence pack valid: {run_dir}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create and validate HydraCam evidence verification packs",
    )
    subparsers = parser.add_subparsers(dest="command_name", required=True)

    start = subparsers.add_parser("start", help="Create a verification pack")
    start.add_argument("--item", required=True)
    start.add_argument("--slug")
    start.add_argument("--source", required=True)
    start.add_argument("--tier", required=True, choices=sorted(TIERS))
    start.add_argument("--timestamp")
    start.add_argument("--acceptance", action="append", default=[])
    start.add_argument("--require-screenshots", action="store_true")
    start.add_argument("--require-video", action="store_true")
    start.add_argument("--require-device-logs", action="store_true")
    start.set_defaults(func=start_command)

    run = subparsers.add_parser("run", help="Run a command and log its output")
    run.add_argument("run_dir")
    run.add_argument("command", nargs=argparse.REMAINDER)
    run.set_defaults(func=run_command)

    finalize = subparsers.add_parser("finalize", help="Finalize a verification pack")
    finalize.add_argument("run_dir")
    finalize.add_argument(
        "--status",
        required=True,
        choices=("passed", "failed", "blocked", "partial"),
    )
    finalize.add_argument("--note", action="append", default=[])
    finalize.set_defaults(func=finalize_command)

    device = subparsers.add_parser("add-device", help="Record a device under test")
    device.add_argument("run_dir")
    device.add_argument("--name", required=True)
    device.add_argument("--kind", required=True)
    device.add_argument("--identifier", required=True)
    device.add_argument("--role", required=True)
    device.add_argument("--os", required=True)
    device.add_argument("--note", action="append", default=[])
    device.set_defaults(func=add_device_command)

    check = subparsers.add_parser("check", help="Validate a verification pack")
    check.add_argument("run_dir")
    check.set_defaults(func=check_command)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
