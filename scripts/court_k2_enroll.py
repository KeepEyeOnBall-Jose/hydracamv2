#!/usr/bin/env python3
"""Enroll or re-enroll court phones against K2 Court Cloud (C1 1.29).

Supports two clean workflows:
1. Canonical K2 single-device-record enrollment (default):
     python3 scripts/court_k2_enroll.py --court airport-squash-2 --slot left \\
       --serial RF8M40MT6AW --name court-s10e-3
   Resolves or creates the single device record in K2, upserts hardware
   `adb-serial` / `fleet-host` aliases, verifies `/device/v1/token`, mutes the
   phone, grants Magisk su + freecess whitelist, sends `CourtEnrollReceiver`
   `ENROLL` via root stdin (never argv), and restarts `CourtActivity`.

2. Batch credentials push (`--creds FILE` replacing `k2-enroll.sh`):
     python3 scripts/court_k2_enroll.py --creds ~/.config/hydracam/court-devices.json all
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Callable, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hydracam_lib.adb import DEFAULT_ADB  # noqa: E402
from hydracam_lib.court_enroll_engine import (  # noqa: E402
    DEFAULT_LOCK_DIR,
    StepFailed,
    acquire_lock,
)
from hydracam_lib.court_k2 import (  # noqa: E402
    C1_CONTRACT_VERSION,
    DEFAULT_COURT_PACKAGE,
    DEFAULT_CREDS_FILE,
    DEFAULT_K2_URL,
    CourtEnrollment,
    HttpTransport,
    K2CourtCloudClient,
    K2Error,
    enroll_single_k2_device,
    find_creds_entry,
    load_creds_store,
    resolve_adb_endpoint,
    upsert_creds_entry,
    validate_k2_url,
)
from hydracam_lib.court_phone_device import (  # noqa: E402
    clear_k2_enrollment,
    ensure_silent,
    grant_magisk_su,
    push_k2_enrollment,
    restart_court_app,
    sh,
    whitelist_background,
)
from hydracam_lib.proc import CommandResult, run as proc_run  # noqa: E402


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "targets",
        nargs="*",
        help="Target host/serial/deviceId filters (or 'all') when using --creds.",
    )
    parser.add_argument(
        "--adb",
        default=os.environ.get("ADB", DEFAULT_ADB if Path(DEFAULT_ADB).exists() else "adb"),
        help="Path to adb binary.",
    )
    parser.add_argument(
        "--k2",
        default=os.environ.get("HYDRACAM_K2_URL", DEFAULT_K2_URL),
        help=f"K2 Court Cloud base URL (default: {DEFAULT_K2_URL}).",
    )
    parser.add_argument("--court", help="K2 court slug (e.g. airport-squash-2).")
    parser.add_argument("--slot", help="Court camera slot (e.g. left, center, right).")
    parser.add_argument("--serial", help="Phone ADB serial.")
    parser.add_argument("--host", help="Tailscale hostname (e.g. court-s10e-3).")
    parser.add_argument("--port", type=int, help="Local ADB tunnel port (127.0.0.1:PORT).")
    parser.add_argument("--endpoint", help="Explicit ADB endpoint (overrides discovery).")
    parser.add_argument("--name", help="Human-readable device name in K2.")
    parser.add_argument("--device-id", help="Explicit canonical K2 deviceId to re-enroll.")
    parser.add_argument(
        "--rotate-secret",
        action="store_true",
        help="Force K2 to issue a new device secret (bumps mountRev on same record).",
    )
    parser.add_argument(
        "--skip-aliases",
        action="store_true",
        help="Do not upsert adb-serial / fleet-host aliases in K2.",
    )
    parser.add_argument(
        "--admin-token-env",
        default="COURT_CLOUD_ADMIN_TOKEN",
        help="Environment variable holding the K2 admin bearer token.",
    )
    parser.add_argument(
        "--creds",
        type=Path,
        help="Push existing credentials from a 0600 JSON array file.",
    )
    parser.add_argument(
        "--creds-out",
        type=Path,
        default=DEFAULT_CREDS_FILE,
        help="0600 JSON store to read/update cached device credentials.",
    )
    parser.add_argument(
        "--package",
        default=DEFAULT_COURT_PACKAGE,
        help="Court Android package name.",
    )
    parser.add_argument(
        "--lock-dir",
        type=Path,
        default=DEFAULT_LOCK_DIR,
        help="Shared per-device lock directory.",
    )
    parser.add_argument(
        "--owner",
        default=f"court_k2_enroll:{os.getpid()}",
        help="Lock owner tag.",
    )
    parser.add_argument(
        "--clear",
        action="store_true",
        help="Clear enrollment on the target phone via CourtEnrollReceiver.CLEAR.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Per-command timeout in seconds.",
    )
    return parser.parse_args(list(argv))


def _make_phone_ctx(
    *,
    adb_bin: str,
    endpoint: str,
    runner: Callable[..., CommandResult],
    timeout: int,
) -> SimpleNamespace:
    def _run(cmd: Sequence[str], *, timeout: int = timeout, input_text: str | None = None):
        return runner(list(cmd), timeout=timeout, input_text=input_text)

    return SimpleNamespace(
        adb_bin=adb_bin,
        serial=endpoint,
        run=_run,
        state={},
        paths=None,
        profile={"dnd_sticks": True},
        log=lambda _msg: None,
    )


def _check_root(ctx: SimpleNamespace) -> None:
    res = sh(ctx, 'su -c "id -u"')
    if res["out"].strip() != "0":
        raise StepFailed("su refused over adb", [res["stderr"] or res["stdout"] or "no root"])


def _apply_phone_enrollment(
    ctx: SimpleNamespace,
    enrollment: CourtEnrollment,
    *,
    package_name: str,
) -> None:
    _check_root(ctx)
    grant_magisk_su(ctx, package_name)
    whitelist_background(ctx, package_name)
    # Apply best-effort mute without requiring enroll-state file writes.
    sh(
        ctx,
        "for s in 0 1 2 3 5 6 9 10; do cmd media_session volume --stream $s --set 0 >/dev/null 2>&1; done; "
        "cmd media_session volume --stream 4 --set 1 >/dev/null 2>&1; "
        "settings put system haptic_feedback_enabled 0; "
        "settings put global mode_ringer 0; settings put global zen_mode 2; "
        "cmd notification set_dnd on >/dev/null 2>&1 || true",
    )
    push_k2_enrollment(ctx, enrollment, package_name=package_name)
    restart_court_app(ctx, package_name=package_name)


def _run_clear_mode(
    args: argparse.Namespace,
    *,
    runner: Callable[..., CommandResult],
) -> int:
    ep = resolve_adb_endpoint(
        args.adb,
        serial=args.serial,
        host=args.host,
        port=args.port,
        endpoint=args.endpoint,
        timeout=args.timeout,
        runner=runner,
    )
    lock_key = args.serial or ep
    release = acquire_lock(args.lock_dir, lock_key, args.owner)
    try:
        ctx = _make_phone_ctx(
            adb_bin=args.adb,
            endpoint=ep,
            runner=runner,
            timeout=args.timeout,
        )
        _check_root(ctx)
        clear_k2_enrollment(ctx, package_name=args.package)
        print(f"Cleared K2 enrollment on {ep} ({args.package})")
        return 0
    except StepFailed as exc:
        print(f"FAILED clear on {ep}: {exc}", file=sys.stderr)
        return 1
    finally:
        release()


def _matches_target(row: dict[str, Any], targets: Sequence[str]) -> bool:
    if "all" in targets:
        return True
    candidates = {
        str(row.get("host", "")),
        str(row.get("serial", "")),
        str(row.get("name", "")),
        str(row.get("deviceId", "")),
    }
    return any(t in candidates for t in targets)


def _run_batch_creds_mode(
    args: argparse.Namespace,
    *,
    runner: Callable[..., CommandResult],
    transport: HttpTransport | None,
) -> int:
    if not args.targets:
        print("Pass target serial/host/name or 'all' with --creds.", file=sys.stderr)
        return 2
    if not args.creds.exists():
        print(f"Credentials file not found: {args.creds}", file=sys.stderr)
        return 2
    k2_url_override = validate_k2_url(args.k2) if args.k2 else None
    rows = load_creds_store(args.creds)
    selected = [r for r in rows if _matches_target(r, args.targets)]
    if not selected:
        print("No matching rows in credentials file.", file=sys.stderr)
        return 2

    failures = 0
    for row in selected:
        serial = row.get("serial")
        host = row.get("host")
        port = row.get("port")
        label = host or serial or row.get("deviceId") or "unknown"
        lock_key = str(serial or host or row.get("deviceId"))
        try:
            ep = resolve_adb_endpoint(
                args.adb,
                serial=serial,
                host=host,
                port=int(port) if port is not None else None,
                endpoint=args.endpoint,
                timeout=args.timeout,
                runner=runner,
            )
        except RuntimeError as exc:
            print(f"OFFLINE {label}: {exc}")
            failures += 1
            continue

        try:
            release = acquire_lock(args.lock_dir, lock_key, args.owner)
        except StepFailed as exc:
            print(f"LOCKED  {label}: {exc}")
            failures += 1
            continue

        try:
            eff_k2 = validate_k2_url(str(row.get("k2Url") or k2_url_override))
            court_id = str(row.get("courtId") or "")
            if not court_id and row.get("courtSlug"):
                client = K2CourtCloudClient(eff_k2, transport=transport)
                court_id = str(client.get_court(str(row["courtSlug"]))["id"])
            enrollment = CourtEnrollment(
                k2_url=eff_k2,
                device_id=str(row["deviceId"]),
                secret=str(row["secret"]),
                court_id=court_id,
                slot=str(row["slot"]),
                mount_rev=int(row.get("mountRev", 1)),
                court_slug=row.get("courtSlug"),
                name=host,
            )
            ctx = _make_phone_ctx(
                adb_bin=args.adb,
                endpoint=ep,
                runner=runner,
                timeout=args.timeout,
            )
            _apply_phone_enrollment(ctx, enrollment, package_name=args.package)
            print(
                f"OK      {label} ({ep}) -> {enrollment.court_id}/{enrollment.slot} "
                f"deviceId={enrollment.device_id} mountRev={enrollment.mount_rev}"
            )
        except (K2Error, StepFailed, ValueError, KeyError) as exc:
            print(f"FAILED  {label}: {exc}")
            failures += 1
        finally:
            release()
    return 0 if failures == 0 else 1


def _run_single_k2_enroll(
    args: argparse.Namespace,
    *,
    runner: Callable[..., CommandResult],
    transport: HttpTransport | None,
) -> int:
    if not args.court or not args.slot:
        print(
            "Both --court and --slot are required (unless using --creds or --clear).",
            file=sys.stderr,
        )
        return 2

    k2_url = validate_k2_url(args.k2)
    admin_token = os.environ.get(args.admin_token_env, "")
    if not admin_token:
        print(
            f"Missing K2 admin token in environment variable {args.admin_token_env}.",
            file=sys.stderr,
        )
        return 2

    ep = resolve_adb_endpoint(
        args.adb,
        serial=args.serial,
        host=args.host,
        port=args.port,
        endpoint=args.endpoint,
        timeout=args.timeout,
        runner=runner,
    )
    serial = args.serial
    if not serial:
        probe_ctx = _make_phone_ctx(
            adb_bin=args.adb,
            endpoint=ep,
            runner=runner,
            timeout=args.timeout,
        )
        serial = str(sh(probe_ctx, "getprop ro.serialno")["out"]).strip() or ep

    release = acquire_lock(args.lock_dir, serial, args.owner)
    try:
        client = K2CourtCloudClient(
            k2_url,
            admin_token=admin_token,
            timeout=float(args.timeout),
            transport=transport,
        )
        health = client.health()
        skew = health.get("contractSkew")
        if skew != "same":
            print(
                f"WARN: K2 contractVersion={health.get('contractVersion')} "
                f"vs local {C1_CONTRACT_VERSION} ({skew})"
            )

        existing_creds = load_creds_store(args.creds_out)
        cached = find_creds_entry(
            existing_creds,
            serial=serial,
            host=args.host or args.name,
            device_id=args.device_id,
        )

        outcome = enroll_single_k2_device(
            client=client,
            court_slug=args.court,
            slot=args.slot,
            serial=serial,
            host=args.host or args.name,
            name=args.name or args.host,
            device_id=args.device_id,
            cached_device_id=cached.get("deviceId") if cached else None,
            cached_secret=cached.get("secret") if cached else None,
            rotate_secret=args.rotate_secret,
            sync_aliases=not args.skip_aliases,
        )

        ctx = _make_phone_ctx(
            adb_bin=args.adb,
            endpoint=ep,
            runner=runner,
            timeout=args.timeout,
        )
        _apply_phone_enrollment(ctx, outcome.enrollment, package_name=args.package)
        upsert_creds_entry(
            args.creds_out,
            enrollment=outcome.enrollment,
            serial=serial,
            host=args.host or args.name,
            port=args.port,
        )
        print(
            f"ENROLLED ({outcome.action}) serial={serial} ep={ep} "
            f"deviceId={outcome.enrollment.device_id} "
            f"court={args.court}/{args.slot} mountRev={outcome.enrollment.mount_rev}"
        )
        return 0
    except (K2Error, StepFailed, ValueError, RuntimeError) as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1
    finally:
        release()


def _runner_adapter(
    command: Sequence[str],
    *,
    timeout: int = 30,
    input_text: str | None = None,
) -> CommandResult:
    if input_text is not None:
        import subprocess

        completed = subprocess.run(
            list(command),
            input=input_text,
            check=False,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
        return CommandResult(
            completed.returncode,
            completed.stdout.replace("\r", ""),
            completed.stderr.replace("\r", ""),
        )
    return proc_run(command, timeout=timeout)


def main(
    argv: Sequence[str],
    *,
    runner: Callable[..., CommandResult] | None = None,
    transport: HttpTransport | None = None,
) -> int:
    args = parse_args(argv)
    effective_runner = runner or _runner_adapter

    if args.clear:
        return _run_clear_mode(args, runner=effective_runner)
    if args.creds is not None:
        return _run_batch_creds_mode(
            args,
            runner=effective_runner,
            transport=transport,
        )
    return _run_single_k2_enroll(
        args,
        runner=effective_runner,
        transport=transport,
    )


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
