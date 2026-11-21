"""Resumable step engine for court phone setup: state, locks, reboot budget.

No device-specific or phone-specific logic lives here; see
``court_phone_device.py`` and ``court_enroll_steps.py``.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Sequence

from hydracam_lib.proc import CommandResult

DEFAULT_LOCK_DIR = Path(os.environ.get("HYDRACAM_COURT_LOCK_DIR", "/tmp/court-fleet-locks"))


class StepFailed(Exception):
    """Raised when a setup step hits a precondition, action, or verify failure."""

    def __init__(self, message: str, diagnosis: Sequence[str] = ()) -> None:
        super().__init__(message)
        self.diagnosis = list(diagnosis)


@dataclass(frozen=True)
class EnrollPaths:
    state_dir: Path
    lock_dir: Path
    budget_dir: Path
    creds_file: Path


def default_paths(home: Path | None = None) -> EnrollPaths:
    root = home or Path.home()
    config_root = root / ".config" / "hydracam"
    return EnrollPaths(
        state_dir=Path(
            os.environ.get("HYDRACAM_COURT_STATE_DIR", config_root / "court-enroll")
        ),
        lock_dir=DEFAULT_LOCK_DIR,
        budget_dir=root,
        creds_file=Path(
            os.environ.get("HYDRACAM_COURT_CREDS_FILE", config_root / "court-devices.json")
        ),
    )


def run_command(
    command: Sequence[str],
    *,
    timeout: int = 60,
    input_text: str | None = None,
) -> CommandResult:
    """Run a command without throwing on non-zero exit."""
    try:
        completed = subprocess.run(
            list(command),
            input=input_text,
            check=False,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
        return CommandResult(
            returncode=completed.returncode,
            stdout=completed.stdout.replace("\r", ""),
            stderr=completed.stderr.replace("\r", ""),
        )
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or "") if isinstance(exc.stdout, str) else ""
        err = (exc.stderr or "") if isinstance(exc.stderr, str) else ""
        return CommandResult(returncode=124, stdout=out, stderr=err)


# ---- state file -------------------------------------------------------------


def state_path(paths: EnrollPaths, serial: str) -> Path:
    return paths.state_dir / f"{serial}.json"


def load_state(paths: EnrollPaths, serial: str) -> dict[str, Any]:
    target = state_path(paths, serial)
    if not target.exists():
        return {"serial": serial, "steps": {}}
    data = json.loads(target.read_text(encoding="utf-8"))
    data.setdefault("serial", serial)
    data.setdefault("steps", {})
    return data


def save_state(paths: EnrollPaths, state: dict[str, Any]) -> None:
    """Atomically write non-secret enrollment state with 0o600 permissions."""
    paths.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(paths.state_dir, 0o700)
    sanitized = {k: v for k, v in state.items() if k != "secret"}
    target = state_path(paths, str(sanitized["serial"]))
    tmp = target.with_suffix(".json.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(sanitized, indent=2) + "\n")
    except Exception:
        if tmp.exists():
            tmp.unlink()
        raise
    os.chmod(tmp, 0o600)
    os.replace(tmp, target)


# ---- device lock ------------------------------------------------------------


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def acquire_lock(lock_dir: Path, name: str, owner: str) -> Callable[[], None]:
    """Acquire an atomic mkdir lock at ``lock_dir/name``, taking over dead PIDs."""
    lock_dir.mkdir(parents=True, exist_ok=True)
    target = lock_dir / name
    owner_file = target / "owner"
    now_iso = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    line = f"{owner}\tpid={os.getpid()}\thost={socket.gethostname()}\t{now_iso}\n"
    try:
        target.mkdir()
    except FileExistsError:
        held = (
            owner_file.read_text(encoding="utf-8").strip()
            if owner_file.exists()
            else "(no owner file)"
        )
        held_tag = held.split("\t", 1)[0]
        pid_match = re.search(r"pid=(\d+)", held)
        pid = int(pid_match.group(1)) if pid_match else 0
        stale = bool(
            re.match(r"^(?:court_phone_setup|court_k2_enroll|enroll\.mjs)", held_tag)
            and pid
            and not _pid_alive(pid)
        )
        if held_tag != owner and not stale:
            raise StepFailed(
                f"{target} is held",
                [
                    f"owner: {held}",
                    "Another session owns this phone. Coordinate with it; do not delete the lock.",
                    f"If that session is yours, pass --owner '{held_tag}'.",
                ],
            )
    owner_file.write_text(line, encoding="utf-8")
    return lambda: shutil.rmtree(target, ignore_errors=True)


# ---- reboot budget ----------------------------------------------------------


def iso_utc(now_ms: int) -> str:
    dt = datetime.fromtimestamp(now_ms / 1000.0, tz=timezone.utc)
    return dt.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def budget_file(budget_dir: Path, now_ms: int) -> Path:
    dt = datetime.fromtimestamp(now_ms / 1000.0, tz=timezone.utc)
    ymd = dt.strftime("%Y%m%d")
    return budget_dir / f".court-reboot-budget-{ymd}.log"


def reboots_used(file_path: Path) -> int:
    if not file_path.exists():
        return 0
    return sum(
        1
        for line in file_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    )


def reserve_reboot(ctx: Any, reason: str) -> None:
    """Append a reboot record BEFORE causing/asking for a reboot; refuse at cap."""
    file_path = budget_file(ctx.paths.budget_dir, ctx.now())
    used = reboots_used(file_path)
    if used >= ctx.reboot_cap:
        raise StepFailed(
            f"reboot budget exhausted: {used}/{ctx.reboot_cap} in {file_path}",
            [
                "Every phone boot buzzes. The shared daily cap is reached.",
                "Raise --reboot-cap only if authorized, or resume tomorrow.",
            ],
        )
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with file_path.open("a", encoding="utf-8") as handle:
        handle.write(f"{iso_utc(ctx.now())}\t{ctx.serial}\t{ctx.owner}\t{reason}\n")
    ctx.log(f"reboot budget: {used + 1}/{ctx.reboot_cap} ({reason})")


# ---- human steps & polling --------------------------------------------------


def poll_until(
    ctx: Any,
    check: Callable[[], Any],
    *,
    timeout_ms: int,
    poll_ms: int = 3000,
) -> Any:
    deadline = ctx.now() + timeout_ms
    while True:
        result = check()
        if result:
            return result
        if ctx.now() >= deadline:
            return None
        ctx.sleep(poll_ms)


def human_step(
    ctx: Any,
    *,
    title: str,
    lines: Sequence[str],
    until: Callable[[], Any],
    timeout_ms: int,
    poll_ms: int = 3000,
    instead: Sequence[tuple[str, str]] = (),
    waiting: str | None = None,
) -> Any:
    ctx.say("")
    ctx.say(f">>> HUMAN: {title}")
    for i, line in enumerate(lines, start=1):
        ctx.say(f"  {i}. {line}")
    if waiting:
        ctx.say(f"  (waiting for: {waiting})")
    deadline = ctx.now() + timeout_ms
    while True:
        result = until()
        if result:
            return result
        if ctx.now() >= deadline:
            break
        ctx.sleep(poll_ms)
    raise StepFailed(
        f"timed out after {round(timeout_ms / 1000)} s: {title}",
        [
            "What you might see instead:",
            *[f"  - {see}: {meaning}" for see, meaning in instead],
        ],
    )


# ---- step runner ------------------------------------------------------------


def run_steps(
    ctx: Any,
    steps: Sequence[Any],
    *,
    from_step: str | None = None,
) -> dict[str, Any]:
    state = ctx.state
    if from_step:
        indices = [i for i, step in enumerate(steps) if step.id == from_step]
        if not indices:
            known = " ".join(step.id for step in steps)
            raise StepFailed(f"unknown step {from_step}", [f"steps: {known}"])
        from_index = indices[0]
        for step in steps[from_index:]:
            state["steps"].pop(step.id, None)
    else:
        from_index = 0

    total = len(steps)
    for index, step in enumerate(steps):
        label = f"[{index + 1:02d}/{total}] {step.id}"
        record = state["steps"].get(step.id)
        if index < from_index or (
            record and record.get("status") == "verified" and not step.always
        ):
            earlier = record.get("at", "earlier") if record else "earlier"
            ctx.say(f"{label}: skip (verified {earlier})")
            continue
        ctx.say(f"{label}: {step.title}")
        try:
            if step.pre:
                pre = step.pre(ctx)
                if not pre.get("ok"):
                    raise StepFailed(
                        f"precondition failed: {pre.get('note')}",
                        pre.get("diagnosis", []),
                    )
            already = step.done(ctx) if step.done else None
            if already:
                ctx.say(f"  already in place: {already}")
            elif step.action:
                step.action(ctx)
            verdict = step.verify(ctx)
            if not verdict.get("ok"):
                raise StepFailed(
                    f"verify failed: {verdict.get('note')}",
                    verdict.get("diagnosis", []),
                )
            state["steps"][step.id] = {
                "status": "verified",
                "at": iso_utc(ctx.now()),
                "note": verdict.get("note") or already or "",
            }
            save_state(ctx.paths, state)
            ctx.say(f"  verified: {verdict.get('note') or 'ok'}")
        except StepFailed as exc:
            state["steps"][step.id] = {
                "status": "failed",
                "at": iso_utc(ctx.now()),
                "note": str(exc),
                "diagnosis": exc.diagnosis,
            }
            save_state(ctx.paths, state)
            ctx.say(f"  STOPPED at {step.id}: {exc}")
            for line in exc.diagnosis:
                ctx.say(f"    {line}")
            ctx.say("  Fix the cause, then re-run; verified steps are skipped.")
            return {"ok": False, "failedAt": step.id}
    return {"ok": True}
