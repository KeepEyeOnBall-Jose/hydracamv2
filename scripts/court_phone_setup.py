#!/usr/bin/env python3
"""Resumable court phone bring-up and K2 Court Cloud enrollment CLI.

Ported and adapted from media-timeline `court-fleet/enroll` to live in
`hydracamv2` and enroll directly against K2 Court Cloud's canonical C1 1.29
single device record (with zero hardcoded passwords, tokens, or MT paths).
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Callable, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hydracam_lib.adb import DEFAULT_ADB  # noqa: E402
from hydracam_lib.court_enroll_engine import (  # noqa: E402
    StepFailed,
    acquire_lock,
    budget_file,
    default_paths,
    load_state,
    reboots_used,
    run_command,
    save_state,
)
from hydracam_lib.court_enroll_steps import add_wifi, build_steps  # noqa: E402
from hydracam_lib.court_k2 import (  # noqa: E402
    DEFAULT_COURT_PACKAGE,
    DEFAULT_K2_URL,
    HttpTransport,
    K2CourtCloudClient,
    K2Error,
    validate_k2_url,
)
from hydracam_lib.court_phone_device import (  # noqa: E402
    adb_state,
    getprop,
    parse_wifi_tsv,
)
from hydracam_lib.court_profiles import profile_for  # noqa: E402


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bring up and enroll a Samsung court phone with K2 Court Cloud (C1 1.29).",
    )
    parser.add_argument("serial", nargs="?", help="Phone USB/ADB serial.")
    parser.add_argument("--name", help="Court phone name/hostname (e.g. court-s10e-4).")
    parser.add_argument("--port", help="Optional local ADB tunnel port (4-5 digits).")
    parser.add_argument("--from", dest="from_step", help="Resume from STEP id (clears later steps).")
    parser.add_argument("--status", action="store_true", help="Print step statuses and exit.")
    parser.add_argument("--model", help="Phone model (e.g. SM-G970F) when adb is unavailable.")
    parser.add_argument(
        "--kit",
        type=Path,
        default=Path.home() / "court-root-mbp",
        help="Root kit directory containing firmware images, Magisk.apk, and heimdall-cli.",
    )
    parser.add_argument("--apk", type=Path, help="Path to HydraCam court-flavor APK.")
    parser.add_argument("--package", default=DEFAULT_COURT_PACKAGE, help="Court app package name.")
    parser.add_argument("--wifi", help="Preferred Wi-Fi SSID from --wifi-file.")
    parser.add_argument(
        "--wifi-file",
        type=Path,
        default=Path(os.environ.get("HYDRACAM_COURT_WIFI_TSV", Path.home() / ".config" / "hydracam" / "wifi.tsv")),
        help="External (untracked) wifi.tsv path.",
    )
    parser.add_argument("--owner", help="Device lock owner tag.")
    parser.add_argument(
        "--reboot-cap",
        type=int,
        default=int(os.environ.get("COURT_REBOOT_CAP", "20")),
        help="Daily shared reboot budget cap.",
    )
    parser.add_argument("--k2", default=os.environ.get("HYDRACAM_K2_URL", DEFAULT_K2_URL), help="K2 Court Cloud URL.")
    parser.add_argument("--court", help="K2 court slug (e.g. airport-squash-2).")
    parser.add_argument("--slot", help="K2 camera slot (e.g. left, center, right).")
    parser.add_argument("--device-id", help="Explicit canonical K2 deviceId.")
    parser.add_argument("--rotate-secret", action="store_true", help="Rotate device secret in K2.")
    parser.add_argument("--admin-token-env", default="COURT_CLOUD_ADMIN_TOKEN", help="Env var with K2 admin token.")
    parser.add_argument("--skip-k2", action="store_true", help="Skip K2 Court Cloud enrollment step.")
    parser.add_argument("--skip-remote-access", action="store_true", help="Skip Termux sshd setup step.")
    parser.add_argument("--tailscale-rollout", type=Path, help="Optional Tailscale rollout script path.")
    parser.add_argument("--skip-tailscale", action="store_true", help="Skip Tailscale rollout step.")
    parser.add_argument("--jump-host", default="", help="Optional SSH jump host for Tailscale rollout.")
    parser.add_argument("--google-account", help="Optional fleet Google account email (skipped if omitted).")
    parser.add_argument("--google-keychain-service", default="hydracam-fleet-google", help="Keychain service for Google password.")
    parser.add_argument("--skip-google", action="store_true", help="Skip optional Google account step.")
    parser.add_argument("--pin-keychain-service", default="hydracam-court-screen-pin", help="Keychain service for screen PIN.")
    parser.add_argument("--pin-keychain-account", help="Keychain account for screen PIN (defaults to phone serial).")
    parser.add_argument("--skip-pin", action="store_true", help="Skip screen PIN lock step.")
    parser.add_argument("--lock-dir", type=Path, help="Override shared lock directory.")
    parser.add_argument("--state-dir", type=Path, help="Override enroll state directory.")
    parser.add_argument("--creds-file", type=Path, help="Override 0600 credentials JSON file.")
    parser.add_argument(
        "--adb",
        default=os.environ.get("ADB", DEFAULT_ADB if Path(DEFAULT_ADB).exists() else "adb"),
        help="Path to adb binary.",
    )
    parser.add_argument(
        "--allow-untested",
        action="store_true",
        help="Allow models not yet verified end-to-end.",
    )
    args = parser.parse_args(list(argv))

    if args.port is not None:
        if not re.match(r"^\d{4,5}$", str(args.port)):
            raise ValueError("--port must be a 4-5 digit number")
        args.port = int(args.port)
    if args.name is not None and not re.match(r"^court-[a-z0-9-]+$", args.name):
        raise ValueError("--name must look like court-s10e-4")
    if args.k2:
        args.k2 = validate_k2_url(args.k2)
    return args


class SetupContext:
    """Runtime context shared across all enrollment steps."""

    def __init__(
        self,
        *,
        serial: str,
        home: Path,
        opts: argparse.Namespace,
        paths: Any,
        state: dict[str, Any],
        profile: dict[str, Any],
        kit: Path,
        heimdall: str,
        owner: str,
        reboot_cap: int,
        now: Callable[[], int],
        sleep: Callable[[int], None],
        say: Callable[[str], None],
        log: Callable[[str], None],
        run: Callable[..., Any],
        confirm: Callable[[str], bool],
        out: list[str] | None = None,
        wifi_file: Path | None = None,
        adb_bin: str = "adb",
        k2_transport: HttpTransport | None = None,
        admin_token: str | None = None,
    ) -> None:
        self.serial = serial
        self.home = home
        self.opts = opts
        self.paths = paths
        self.state = state
        self.profile = profile
        self.kit = kit
        self.heimdall = heimdall
        self.owner = owner
        self.reboot_cap = reboot_cap
        self.now = now
        self.sleep = sleep
        self.say = say
        self.log = log
        self.run = run
        self.confirm = confirm
        self.out = out if out is not None else []
        self.wifi_file = wifi_file or opts.wifi_file
        self.adb_bin = adb_bin
        self.k2_transport = k2_transport
        self.admin_token = admin_token

        self.name: str | None = opts.name or state.get("name")
        self.port: int | None = opts.port if opts.port is not None else state.get("port")
        self._releases: list[Callable[[], None]] = []
        self._serial_locked = False
        self._download_locked = False

    def wifi(self) -> None:
        add_wifi(self)

    def wifi_ssid(self) -> str:
        if not self.wifi_file or not Path(self.wifi_file).exists():
            return "(wifi.tsv not configured)"
        rows = parse_wifi_tsv(Path(self.wifi_file).read_text(encoding="utf-8"))
        match = next((r for r in rows if r["ssid"] == self.opts.wifi), rows[0] if rows else None)
        return match["ssid"] if match else "(wifi.tsv is empty)"

    def take_download_lock(self) -> None:
        acquire_lock(self.paths.lock_dir, "download-mode", f"{self.owner}:{self.serial}")
        self._download_locked = True

    def release_download_lock(self) -> None:
        if not self._download_locked:
            return
        import shutil

        shutil.rmtree(self.paths.lock_dir / "download-mode", ignore_errors=True)
        self._download_locked = False

    def release_all(self) -> None:
        while self._releases:
            release = self._releases.pop(0)
            release()

    def authorized_keys(self) -> Path:
        pub = self.home / ".ssh" / "court_phones_ed25519.pub"
        if not pub.exists():
            raise StepFailed(
                f"missing {pub}",
                ["Generate or install the court phone ssh public key before remote-access."],
            )
        target = self.paths.state_dir / "authorized_keys"
        self.paths.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        target.write_text(pub.read_text(encoding="utf-8"), encoding="utf-8")
        return target

    def preflight(self) -> dict[str, Any]:
        if not self._serial_locked:
            self._releases.append(acquire_lock(self.paths.lock_dir, self.serial, self.owner))
            self._serial_locked = True
        problems: list[str] = []
        if not self.name:
            problems.append("--name is required on the first run")
        if self.run([self.heimdall, "version"]).returncode != 0:
            problems.append(f"heimdall missing or broken at {self.heimdall}")
        for image in self.profile["images"]:
            img_path = self.kit / image["file"]
            if not img_path.exists():
                problems.append(f"kit image missing: {img_path}")
                continue
            if image.get("bytes") and img_path.stat().st_size != image["bytes"]:
                problems.append(
                    f"{image['file']}: {img_path.stat().st_size} bytes, expected {image['bytes']}"
                )
            elif image.get("sha1"):
                actual = hashlib.sha1(img_path.read_bytes()).hexdigest()
                if actual != image["sha1"]:
                    problems.append(f"{image['file']}: sha1 mismatch")
        if not getattr(self.opts, "skip_k2", False) and self.opts.court and self.opts.slot:
            try:
                client = K2CourtCloudClient(
                    self.opts.k2,
                    admin_token=self.admin_token or os.environ.get(self.opts.admin_token_env, ""),
                    transport=self.k2_transport,
                )
                court = client.get_court(self.opts.court)
                slots = {c.get("slot") for c in court.get("cameras", [])}
                if self.opts.slot not in slots:
                    problems.append(f"K2 court {self.opts.court} has no slot {self.opts.slot}")
            except K2Error as exc:
                problems.append(f"K2 preflight failed: {exc}")

        used = reboots_used(budget_file(self.paths.budget_dir, self.now()))
        if problems:
            return {"ok": False, "note": problems[0], "diagnosis": problems}
        self.state["name"] = self.name
        if self.port is not None:
            self.state["port"] = self.port
        self.state["profile"] = self.profile["model"]
        save_state(self.paths, self.state)
        return {
            "ok": True,
            "note": f"{self.name}, reboots today {used}/{self.reboot_cap}",
        }


def _resolve_profile(ctx: SetupContext) -> dict[str, Any]:
    model = ctx.opts.model or ctx.state.get("model")
    if not model and adb_state(ctx) == "device":
        model = getprop(ctx, "ro.product.model")
    if not model:
        raise StepFailed(
            "cannot read the phone model",
            ["Pass --model (e.g. SM-G970F) or plug the phone in with USB debugging on."],
        )
    return profile_for(model)


def print_status(ctx: SetupContext, steps: Sequence[Any]) -> None:
    ctx.say(f"{ctx.serial} {ctx.state.get('model', '')} {ctx.state.get('name', '')}")
    for idx, step in enumerate(steps, start=1):
        rec = ctx.state["steps"].get(step.id)
        summary = f"{rec['status']} {rec['at']} {rec.get('note', '')}" if rec else "-"
        ctx.say(f"  {idx:2d}. {step.id:<18} {summary}")


def main(
    argv: Sequence[str],
    *,
    home: Path | None = None,
    run: Callable[..., Any] | None = None,
    say: Callable[[str], None] | None = None,
    log: Callable[[str], None] | None = None,
    k2_transport: HttpTransport | None = None,
    admin_token: str | None = None,
) -> int:
    try:
        opts = parse_args(argv)
    except ValueError as exc:
        print(f"argument error: {exc}", file=sys.stderr)
        return 2

    if not opts.serial:
        print("usage: court_phone_setup.py SERIAL --name court-<model>-<n> [options]", file=sys.stderr)
        return 2

    eff_home = home or Path.home()
    paths = default_paths(eff_home)
    if opts.lock_dir is not None or opts.state_dir is not None or opts.creds_file is not None:
        from hydracam_lib.court_enroll_engine import EnrollPaths

        paths = EnrollPaths(
            state_dir=opts.state_dir or paths.state_dir,
            lock_dir=opts.lock_dir or paths.lock_dir,
            budget_dir=paths.budget_dir,
            creds_file=opts.creds_file or paths.creds_file,
        )

    eff_say = say or print
    eff_log = log or (lambda line: print(f"  . {line}"))
    eff_run = run or run_command
    state = load_state(paths, opts.serial)

    ctx = SetupContext(
        serial=opts.serial,
        home=eff_home,
        opts=opts,
        paths=paths,
        state=state,
        profile={},
        kit=opts.kit,
        heimdall=str(opts.kit / "heimdall-cli"),
        owner=opts.owner or f"court_phone_setup:{os.getpid()}",
        reboot_cap=opts.reboot_cap,
        now=lambda: int(time.time() * 1000),
        sleep=lambda ms: time.sleep(ms / 1000.0),
        say=eff_say,
        log=eff_log,
        run=eff_run,
        confirm=lambda prompt: (input(f"  {prompt} ") or True) and True,
        adb_bin=opts.adb,
        k2_transport=k2_transport,
        admin_token=admin_token,
    )

    try:
        ctx.profile = _resolve_profile(ctx)
        steps = build_steps(ctx.profile)
        if opts.status:
            print_status(ctx, steps)
            return 0
        if not ctx.profile["tested"] and not opts.allow_untested:
            ctx.say(
                f"{ctx.profile['model']} ({ctx.profile['label']}) has never been enrolled end to end."
            )
            ctx.say("Re-run with --allow-untested to try it, and update court_profiles.py from what you see.")
            return 2
        result = __import__("hydracam_lib.court_enroll_engine", fromlist=["run_steps"]).run_steps(
            ctx, steps, from_step=opts.from_step
        )
        if result["ok"]:
            ctx.say(f"DONE: {ctx.name} {ctx.serial} enrolled.")
            return 0
        return 1
    except StepFailed as exc:
        ctx.say(f"STOPPED: {exc}")
        for line in exc.diagnosis:
            ctx.say(f"  {line}")
        return 1
    finally:
        ctx.release_all()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
