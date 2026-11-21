"""ADB, USB, Heimdall, Keychain, silence, secret push, UI, and court-app helpers.

Never run ``adb kill-server``: other sessions and services share the server.
"""

from __future__ import annotations

import os
import re
import shlex
import shutil
import tempfile
from pathlib import Path
from typing import Any, Callable, Sequence

from hydracam_lib.court_enroll_engine import StepFailed, save_state
from hydracam_lib.court_k2 import (
    COURT_ACTIVITY,
    DEFAULT_COURT_PACKAGE,
    CourtEnrollment,
)

# Samsung idProduct 0x685D (26717) = download mode / bootloader.
DOWNLOAD_PRODUCT = 26717

_PLACEHOLDER_RE = re.compile(
    r"^(|<.*>|\*+|x+|password|placeholder|changeme|secret|\.\.\.)$",
    re.IGNORECASE,
)

SILENCE_PROBE = (
    'echo "@haptic $(settings get system haptic_feedback_enabled)"; '
    'echo "@zen $(settings get global zen_mode)"; '
    'for s in 3 2; do echo "@vol$s $( (cmd media_session volume --stream $s --get '
    '|| media volume --stream $s --get) 2>/dev/null | tr \'\\n\' \' \')"; done'
)


def _call_run(
    ctx: Any,
    command: Sequence[str],
    *,
    timeout: int = 60,
    input_text: str | None = None,
):
    return ctx.run(list(command), timeout=timeout, input_text=input_text)


def adb(
    ctx: Any,
    args: Sequence[str],
    *,
    timeout: int = 60,
    input_text: str | None = None,
    serial_override: str | None = None,
):
    adb_bin = getattr(ctx, "adb_bin", "adb")
    target = serial_override or ctx.serial
    return _call_run(
        ctx,
        [adb_bin, "-s", target, *args],
        timeout=timeout,
        input_text=input_text,
    )


def sh(
    ctx: Any,
    command: str,
    *,
    timeout: int = 60,
    input_text: str | None = None,
    serial_override: str | None = None,
) -> dict[str, Any]:
    res = adb(
        ctx,
        ["shell", command],
        timeout=timeout,
        input_text=input_text,
        serial_override=serial_override,
    )
    return {
        "code": res.returncode,
        "stdout": res.stdout,
        "stderr": res.stderr,
        "out": res.stdout.strip(),
    }


def getprop(ctx: Any, name: str) -> str:
    return str(sh(ctx, f"getprop {name}")["out"])


def adb_state(ctx: Any) -> str | None:
    adb_bin = getattr(ctx, "adb_bin", "adb")
    res = _call_run(ctx, [adb_bin, "devices"])
    for line in res.stdout.splitlines():
        parts = line.strip().split()
        if len(parts) >= 2 and parts[0] == ctx.serial:
            return parts[1]
    return None


def usb_present(ctx: Any) -> bool:
    res = _call_run(ctx, ["ioreg", "-p", "IOUSB", "-l", "-w0"])
    return f'"USB Serial Number" = "{ctx.serial}"' in res.stdout


def usb_product(ctx: Any) -> int | None:
    res = _call_run(ctx, ["ioreg", "-p", "IOUSB", "-l", "-w0"])
    needle = f'"USB Serial Number" = "{ctx.serial}"'
    block = next(
        (part for part in res.stdout.split("+-o ") if needle in part),
        None,
    )
    if block is None:
        return None
    match = re.search(r'"idProduct"\s*=\s*(\d+)', block)
    return int(match.group(1)) if match else 0


def in_download_mode(ctx: Any) -> bool:
    res = _call_run(ctx, [ctx.heimdall, "detect"], timeout=20)
    return res.returncode == 0


def keychain(ctx: Any, service: str, account: str) -> str:
    res = _call_run(
        ctx,
        ["security", "find-generic-password", "-s", service, "-a", account, "-w"],
    )
    secret = res.stdout.strip()
    if res.returncode != 0 or not secret:
        raise StepFailed(
            f"Keychain item {service} / {account} not found",
            ["Add it to the login Keychain of this Mac."],
        )
    return secret


# ---- silence ----------------------------------------------------------------


def silence_script(sdk: int) -> str:
    volume = "cmd media_session volume --stream" if sdk >= 28 else "media volume --stream"

    def set_stream(stream: int, value: int) -> str:
        return f"{volume} {stream} --set {value} >/dev/null 2>&1"

    cmds = [set_stream(stream, 0) for stream in (0, 1, 2, 3, 5, 6, 9, 10)]
    cmds.append(set_stream(4, 1))
    cmds.extend(
        [
            "settings put system haptic_feedback_enabled 0",
            "settings put system vibrate_when_ringing 0",
            "settings put system sound_effects_enabled 0",
            "settings put system lockscreen_sounds_enabled 0",
            "settings put system dtmf_tone 0",
            "settings put global mode_ringer 0",
            "settings put global zen_mode 2",
            "cmd notification set_dnd on >/dev/null 2>&1" if sdk >= 29 else "true",
        ]
    )
    return "; ".join(cmds)


def parse_silence(text: str, *, dnd_sticks: bool) -> list[str]:
    def tag(name: str) -> str:
        match = re.search(rf"^@{name}\s+(.*)$", text, re.MULTILINE)
        return match.group(1).strip() if match else ""

    problems: list[str] = []
    haptic = tag("haptic")
    if haptic != "0":
        problems.append(f"haptics {haptic or 'unknown'}")
    zen = tag("zen")
    if dnd_sticks and zen != "2":
        problems.append(f"zen_mode {zen or 'unknown'}")
    for stream, name in ((3, "music"), (2, "ring")):
        val = tag(f"vol{stream}")
        if not re.search(r"volume is 0\b", val):
            problems.append(f"{name} stream: {val or 'unknown'}")
    return problems


def ensure_silent(ctx: Any) -> bool:
    """Re-apply mute/DND once per boot_id and verify it stuck."""
    if adb_state(ctx) != "device":
        return False
    boot = str(sh(ctx, "cat /proc/sys/kernel/random/boot_id")["out"])
    if not boot or ctx.state.get("silencedBootId") == boot:
        return False
    raw_sdk = getprop(ctx, "ro.build.version.sdk")
    sdk = int(raw_sdk) if raw_sdk.isdigit() else 0
    sh(ctx, silence_script(sdk))
    probe = str(sh(ctx, SILENCE_PROBE)["out"])
    dnd_sticks = bool(getattr(ctx, "profile", {}).get("dnd_sticks", True))
    problems = parse_silence(probe, dnd_sticks=dnd_sticks)
    if problems:
        raise StepFailed(
            "phone is not silent after boot",
            [*problems, "Court phones must make no sound and no vibration."],
        )
    ctx.state["silencedBootId"] = boot
    save_state(ctx.paths, ctx.state)
    ctx.log(f"silenced (boot {boot[:8]})")
    return True


# ---- secrets & Wi-Fi --------------------------------------------------------


def push_secret_file(ctx: Any, content: str, remote: str) -> None:
    """Write ``content`` to a 0600 temp file, push to phone, and remove local."""
    temp_dir = Path(tempfile.mkdtemp(prefix="hydracam-enroll-"))
    local_file = temp_dir / "secret"
    try:
        fd = os.open(local_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.chmod(local_file, 0o600)
        pushed = adb(ctx, ["push", str(local_file), remote])
        if pushed.returncode != 0:
            raise StepFailed(f"adb push to {remote} failed", [])
        sh(ctx, f"chmod 600 {shlex.quote(remote)}")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def parse_wifi_tsv(
    text: str,
    *,
    keychain_lookup: Callable[[str, str], str] | None = None,
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for raw_line in text.splitlines():
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        parts = raw_line.split("\t")
        ssid = parts[0].strip() if parts else ""
        password = parts[1].rstrip("\r") if len(parts) > 1 else ""
        flags = parts[2].strip() if len(parts) > 2 else ""
        if password.startswith("@keychain:") and keychain_lookup is not None:
            service = password.removeprefix("@keychain:").strip()
            password = keychain_lookup(service, ssid)
        rows.append({"ssid": ssid, "password": password, "flags": flags})
    return rows


def wifi_script(
    rows: Sequence[dict[str, str]],
    preferred: str | None,
    sdk: int,
) -> tuple[str, str]:
    if not rows:
        raise StepFailed("wifi.tsv has no networks", ["Add at least one SSID/password row."])
    for row in rows:
        ssid = row.get("ssid", "")
        password = row.get("password", "")
        if not ssid or _PLACEHOLDER_RE.match(password) or len(password) < 8:
            raise StepFailed(
                f'wifi.tsv row for "{ssid}" has no real password',
                ["Refusing to run cmd wifi with a placeholder: it overwrites the saved network."],
            )
    first = next((r for r in rows if r["ssid"] == preferred), rows[0])
    others = [r for r in rows if r is not first]
    lines: list[str] = []
    if sdk >= 31:
        for row in others:
            lines.append(
                f"cmd wifi add-network {shlex.quote(row['ssid'])} wpa2 "
                f"{shlex.quote(row['password'])} >/dev/null 2>&1"
            )
    lines.append(
        f"cmd wifi connect-network {shlex.quote(first['ssid'])} wpa2 "
        f"{shlex.quote(first['password'])} >/dev/null 2>&1 && echo WIFI_OK || echo WIFI_FAILED"
    )
    return "\n".join(lines) + "\n", first["ssid"]


def type_secret(ctx: Any, secret: str) -> None:
    remote = "/data/local/tmp/.enroll-input"
    push_secret_file(ctx, secret.replace(" ", "%s"), remote)
    sh(ctx, f'input text "$(cat {remote})"; rm -f {remote}')


# ---- UI automation ----------------------------------------------------------


def parse_ui(xml: str) -> list[dict[str, Any]]:
    nodes: list[dict[str, Any]] = []
    for match in re.finditer(r"<node\b([^>]*?)/?>", xml):
        attrs: dict[str, Any] = {}
        for attr in re.finditer(r'([\w-]+)="([^"]*)"', match.group(1)):
            attrs[attr.group(1)] = attr.group(2)
        bounds = re.search(
            r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]",
            str(attrs.get("bounds", "")),
        )
        if bounds:
            x1, y1, x2, y2 = (int(bounds.group(i)) for i in range(1, 5))
            attrs["center"] = (round((x1 + x2) / 2), round((y1 + y2) / 2))
        nodes.append(attrs)
    return nodes


def ui_nodes(ctx: Any) -> list[dict[str, Any]]:
    res = sh(
        ctx,
        "uiautomator dump /sdcard/enroll-ui.xml >/dev/null 2>&1; "
        "cat /sdcard/enroll-ui.xml; rm -f /sdcard/enroll-ui.xml",
    )
    return parse_ui(str(res["out"]))


def find_node(
    nodes: Sequence[dict[str, Any]],
    texts: str | Sequence[str],
) -> dict[str, Any] | None:
    wanted = {texts} if isinstance(texts, str) else set(texts)
    return next(
        (
            node
            for node in nodes
            if node.get("text") in wanted or node.get("content-desc") in wanted
        ),
        None,
    )


def tap_text(ctx: Any, texts: str | Sequence[str], *, tries: int = 4) -> bool:
    for _ in range(tries):
        node = find_node(ui_nodes(ctx), texts)
        if node and node.get("center"):
            cx, cy = node["center"]
            sh(ctx, f"input tap {cx} {cy}")
            ctx.sleep(1500)
            return True
        ctx.sleep(1500)
    return False


def focused_node(ctx: Any) -> dict[str, Any] | None:
    return next(
        (node for node in ui_nodes(ctx) if node.get("focused") == "true"),
        None,
    )


# ---- Court app root/freecess/K2 broadcast helpers ---------------------------


def read_package_uid(ctx: Any, package_name: str = DEFAULT_COURT_PACKAGE) -> str:
    """Return Android app UID for ``package_name`` or empty string if absent."""
    res = sh(ctx, f"dumpsys package {shlex.quote(package_name)}")
    match = re.search(r"^\s*userId=(\d+)", res["stdout"], re.MULTILINE)
    return match.group(1) if match else ""


def grant_magisk_su(ctx: Any, package_name: str = DEFAULT_COURT_PACKAGE) -> str:
    """Grant persistent Magisk root policy (policy=2) to ``package_name``."""
    uid = read_package_uid(ctx, package_name)
    if not uid:
        raise StepFailed(
            f"{package_name} is not installed on {ctx.serial}",
            ["Install the court-flavor APK before granting root or enrolling."],
        )
    sql = (
        "INSERT OR REPLACE INTO policies (uid,policy,until,logging,notification) "
        f"VALUES({uid},2,0,1,0)"
    )
    res = sh(ctx, f'su -c "magisk --sqlite \'{sql}\'"')
    if res["code"] != 0:
        raise StepFailed(
            f"Magisk policy insert failed for uid {uid}",
            [res["stderr"] or res["stdout"] or "su / magisk sqlite error"],
        )
    return uid


def whitelist_background(ctx: Any, package_name: str = DEFAULT_COURT_PACKAGE) -> None:
    """Apply Doze / Samsung freecess / standby bucket exemptions to court app."""
    pkg = shlex.quote(package_name)
    cmd = (
        f"dumpsys deviceidle whitelist +{pkg} >/dev/null 2>&1; "
        f"cmd appops set {pkg} RUN_ANY_IN_BACKGROUND allow; "
        f"cmd appops set {pkg} RUN_IN_BACKGROUND allow; "
        f"am set-standby-bucket {pkg} active; "
        f"am set-inactive {pkg} false"
    )
    sh(ctx, f"su -c '{cmd}'")


def push_k2_enrollment(
    ctx: Any,
    enrollment: CourtEnrollment,
    *,
    package_name: str = DEFAULT_COURT_PACKAGE,
) -> None:
    """Send CourtEnrollReceiver ENROLL broadcast over root ``su`` stdin."""
    broadcast_cmd = enrollment.build_enroll_broadcast_command(package_name)
    res = sh(ctx, "su", input_text=f"{broadcast_cmd}\n")
    if res["code"] != 0 or 'data="ok"' not in res["stdout"]:
        tail = res["out"].splitlines()[-1] if res["out"] else res["stderr"]
        raise StepFailed(
            f"CourtEnrollReceiver rejected enrollment: {tail or 'unknown error'}",
            ["Verify court app version and root su access."],
        )


def clear_k2_enrollment(
    ctx: Any,
    *,
    package_name: str = DEFAULT_COURT_PACKAGE,
) -> None:
    """Send CourtEnrollReceiver CLEAR broadcast over root ``su`` stdin."""
    broadcast_cmd = CourtEnrollment.build_clear_broadcast_command(package_name)
    res = sh(ctx, "su", input_text=f"{broadcast_cmd}\n")
    if res["code"] != 0 or 'data="ok"' not in res["stdout"]:
        tail = res["out"].splitlines()[-1] if res["out"] else res["stderr"]
        raise StepFailed(
            f"CourtEnrollReceiver CLEAR failed: {tail or 'unknown error'}",
            ["Verify court app is installed and rooted."],
        )


def restart_court_app(ctx: Any, *, package_name: str = DEFAULT_COURT_PACKAGE) -> None:
    pkg = shlex.quote(package_name)
    activity = shlex.quote(f"{package_name}/{COURT_ACTIVITY}")
    res = sh(ctx, f"am force-stop {pkg}; am start -n {activity}")
    if res["code"] != 0:
        raise StepFailed(
            f"Failed to restart {package_name}",
            [res["stderr"] or res["stdout"]],
        )
