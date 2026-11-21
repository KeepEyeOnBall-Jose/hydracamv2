"""Ordered court phone bring-up and K2 Court Cloud enrollment steps.

Order invariant (prevents Samsung S10e boot loops and satisfies KnoxGuard):
  identify -> oem-unlock -> bootloader-unlock -> kg-online -> download-mode
  -> flash (--no-reboot) -> recovery-wipe -> ONE minimal setup -> verify-unlock
  -> wifi -> root-boot -> magisk-shell -> remote-access -> [tailscale]
  -> hardening -> [google-account] -> hydracam (court flavor) -> [pin-lock]
  -> k2-enroll (canonical C1 1.29 single device record) -> reboot-test
"""

from __future__ import annotations

import hashlib
import os
import shlex
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Sequence

from hydracam_lib.court_enroll_engine import (
    StepFailed,
    human_step,
    poll_until,
    reserve_reboot,
    save_state,
)
from hydracam_lib.court_k2 import (
    DEFAULT_COURT_PACKAGE,
    K2CourtCloudClient,
    K2Error,
    enroll_single_k2_device,
    find_creds_entry,
    load_creds_store,
    upsert_creds_entry,
)
from hydracam_lib.court_phone_device import (
    DOWNLOAD_PRODUCT,
    adb,
    adb_state,
    ensure_silent,
    focused_node,
    getprop,
    grant_magisk_su,
    in_download_mode,
    keychain,
    parse_wifi_tsv,
    push_k2_enrollment,
    push_secret_file,
    read_package_uid,
    restart_court_app,
    sh,
    tap_text,
    type_secret,
    usb_present,
    usb_product,
    whitelist_background,
    wifi_script,
)
from hydracam_lib.court_profiles import keys_text

MIN = 60_000
PHONE_SETUP_DIR = Path(__file__).resolve().parents[1] / "court_phone_setup"


def ok(note: str = "ok") -> dict[str, Any]:
    return {"ok": True, "note": note}


def bad(note: str, diagnosis: Sequence[str] = ()) -> dict[str, Any]:
    return {"ok": False, "note": note, "diagnosis": list(diagnosis)}


@dataclass
class Step:
    id: str
    title: str
    verify: Callable[[Any], dict[str, Any]]
    always: bool = False
    pre: Callable[[Any], dict[str, Any]] | None = None
    done: Callable[[Any], str | None] | None = None
    action: Callable[[Any], None] | None = None


class BootLoop(Exception):
    """Raised when USB disappears for > loop_after_ms right after flashing."""


def _need_device(ctx: Any) -> dict[str, Any]:
    state = adb_state(ctx)
    if state == "device":
        ensure_silent(ctx)
        return ok("adb device")
    hint = (
        'Tap "Allow" on the phone (tick "Always allow").'
        if state == "unauthorized"
        else "Plug the phone into THIS Mac by USB with USB debugging on."
    )
    return bad(f"adb state is {state or 'absent'}", [hint])


def _is_root(ctx: Any) -> bool:
    return bool(re_uid0(str(sh(ctx, "su -c id")["out"])))


def re_uid0(text: str) -> bool:
    return "uid=0" in text


def _magiskd_running(ctx: Any) -> bool:
    return "magiskd" in str(sh(ctx, "ps -A")["out"])


def usb_watch(
    ctx: Any,
    *,
    stable_ms: int = 60_000,
    loop_after_ms: float = float("inf"),
    need_absence_first: bool = False,
) -> Callable[[], bool]:
    """Poll check returning True once phone stays in Android/recovery USB."""
    last_seen = ctx.now()
    android_since: int | None = None
    was_absent = not need_absence_first

    def check() -> bool:
        nonlocal last_seen, android_since, was_absent
        product = usb_product(ctx)
        now = ctx.now()
        if product is None:
            was_absent = True
        else:
            last_seen = now
        if product is not None and product != DOWNLOAD_PRODUCT and was_absent:
            android_since = android_since if android_since is not None else now
        else:
            android_since = None
        if now - last_seen > loop_after_ms:
            raise BootLoop()
        return android_since is not None and (now - android_since) >= stable_ms

    return check


def _recovery_lines(profile: dict[str, Any], *, from_download: bool = False) -> list[str]:
    r = profile["buttons"]["recovery_menu"]
    x = profile["buttons"]["exit_download"]
    lines: list[str] = []
    if from_download:
        lines.extend(
            [
                f"Hold {keys_text(x['keys'])} for about {x['hold_seconds']} s, until {x['until']}.",
                f"The moment it is black, switch to holding {keys_text(r['keys'])}.",
            ]
        )
    else:
        lines.append(f"Phone off (or restarting): hold {keys_text(r['keys'])}.")
    lines.extend(
        [
            f"Release {r['release_first']} when you see {r['release_first_on']}.",
            f"Keep holding {keys_text(r['keep_holding'])} until {r['until']}.",
        ]
    )
    return lines


def _wipe_lines(profile: dict[str, Any], *, from_download: bool = False) -> list[str]:
    return [
        *_recovery_lines(profile, from_download=from_download),
        "In the menu, Volume Down moves, Power selects.",
        'Select "Wipe data/factory reset", then "Factory data reset".',
        'When it says "Data wipe complete", select "Reboot system now".',
    ]


def download_lines(profile: dict[str, Any], *, unlocked: bool) -> list[str]:
    d = profile["buttons"]["download"]
    if d["usb"] == "plug-while-holding":
        lines = [
            "Unplug the USB cable from the phone.",
            "Wait until the screen is completely black (phone off).",
            f"Hold {keys_text(d['keys'])} together.",
            "Keep holding and plug the USB cable in.",
            f"Release both keys on {d['release_on']}.",
        ]
    else:
        lines = [
            f"Phone off, cable plugged in: hold {keys_text(d['keys'])}.",
            f"Release on {d['release_on']}.",
        ]
    if unlocked:
        lines.append(f"Then {profile['buttons']['download_continue']}.")
    return lines


def _wrong_combo_rows(profile: dict[str, Any]) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = [
        (
            'A green "Downloading..." screen',
            "download mode. You cannot unlock from here; hold Volume Down + Power 7 s and start again",
        )
    ]
    if "Bixby" in profile["buttons"]["download"]["keys"]:
        combo = keys_text(profile["buttons"]["download"]["keys"])
        rows.insert(
            0,
            (
                "Only the battery / charging animation",
                f"wrong keys: Volume Up + Volume Down is the S20 FE combo. On this {profile['label']} use {combo}",
            ),
        )
    rows.append(("The phone starts normally", "keys released too early, or not held while plugging in"))
    return rows


def sha1_file(file_path: Path) -> str:
    h = hashlib.sha1()
    h.update(file_path.read_bytes())
    return h.hexdigest()


def _internet(ctx: Any) -> bool:
    res = sh(
        ctx,
        "ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 "
        "&& ping -c 1 -W 5 connectivitycheck.gstatic.com >/dev/null 2>&1 "
        "&& echo NET_OK",
    )
    return "NET_OK" in str(res["out"])


def add_wifi(ctx: Any) -> None:
    """Push Wi-Fi credentials from external TSV using a 0600 temp file."""
    raw_sdk = getprop(ctx, "ro.build.version.sdk")
    sdk = int(raw_sdk) if raw_sdk.isdigit() else 0
    if sdk < 30:
        human_step(
            ctx,
            title="add the court Wi-Fi by hand (Android 10 or older)",
            lines=[f'Settings > Connections > Wi-Fi: join "{ctx.wifi_ssid()}".'],
            waiting="the phone to reach the internet",
            timeout_ms=15 * MIN,
            until=lambda: _internet(ctx),
        )
        return
    if not ctx.wifi_file or not Path(ctx.wifi_file).exists():
        raise StepFailed(
            f"Wi-Fi TSV file missing: {ctx.wifi_file}",
            ["Pass --wifi-file /path/to/wifi.tsv (kept outside git)."],
        )
    rows = parse_wifi_tsv(
        Path(ctx.wifi_file).read_text(encoding="utf-8"),
        keychain_lookup=lambda svc, acct: keychain(ctx, svc, acct),
    )
    script, ssid = wifi_script(rows, ctx.opts.wifi, sdk)
    remote = "/data/local/tmp/.enroll-wifi.sh"
    push_secret_file(ctx, script, remote)
    res = sh(ctx, f"sh {remote}; rm -f {remote}")
    if "WIFI_OK" not in str(res["out"]):
        raise StepFailed(
            f"cmd wifi connect-network {ssid} failed",
            ["Is the network in range? (passwords are not shown)"],
        )
    poll_until(ctx, lambda: _internet(ctx), timeout_ms=90_000, poll_ms=5000)


def boot_loop_rescue(ctx: Any, profile: dict[str, Any]) -> None:
    ctx.say("  BOOT LOOP suspected: the phone has been off USB for over 3 minutes.")
    ctx.say("  Fix: wipe data in recovery. Nothing on the phone is worth keeping yet.")
    reserve_reboot(ctx, "boot-loop recovery wipe")
    human_step(
        ctx,
        title="wipe data in recovery to end the boot loop",
        lines=_wipe_lines(profile, from_download=False),
        waiting="the phone to reach the Welcome screen (60 s steady on USB)",
        timeout_ms=15 * MIN,
        instead=[("Still looping after the wipe", "stop: re-run --from download-mode after flashing stock firmware")],
        until=usb_watch(ctx),
    )


def _setup_human(ctx: Any) -> None:
    watch = usb_watch(ctx, loop_after_ms=3 * MIN)

    def check() -> bool:
        watch()
        return adb_state(ctx) == "device"

    human_step(
        ctx,
        title="minimal setup, then USB debugging (the only setup)",
        lines=[
            "Welcome screen: Start. Skip Wi-Fi (this program adds it), skip every account and Samsung option.",
            'No screen lock: choose "Skip" / "None".',
            'Settings > About phone > Software information: tap "Build number" 7 times.',
            'Settings > Developer options: turn on "USB debugging".',
            'Keep the USB cable plugged into this Mac. Tap "Allow" and tick "Always allow from this computer".',
        ],
        waiting="adb to show the phone as authorized",
        timeout_ms=30 * MIN,
        instead=[
            ("The phone keeps restarting (logo, black, logo)", "boot loop: detected after 3 min off USB"),
            ('No "Allow" prompt', "unplug and replug the cable; check USB debugging is on"),
        ],
        until=check,
    )


def _make_k2_client(ctx: Any) -> K2CourtCloudClient:
    token = getattr(ctx, "admin_token", None) or os.environ.get(
        ctx.opts.admin_token_env, ""
    )
    return K2CourtCloudClient(
        ctx.opts.k2,
        admin_token=token or None,
        transport=getattr(ctx, "k2_transport", None),
    )


def _device_record_in_k2(client: K2CourtCloudClient, device_id: str) -> dict[str, Any] | None:
    try:
        devices = client.list_devices()
    except K2Error:
        return None
    return next((d for d in devices if d.get("id") == device_id), None)


def build_steps(profile: dict[str, Any]) -> list[Step]:
    """Return the ordered enrollment steps for ``profile``."""
    model_label = profile["label"]

    def identify_verify(ctx: Any) -> dict[str, Any]:
        model = getprop(ctx, "ro.product.model")
        firmware = getprop(ctx, "ro.build.PDA")
        raw_sdk = getprop(ctx, "ro.build.version.sdk")
        sdk = int(raw_sdk) if raw_sdk.isdigit() else 0
        ctx.state.update({"model": model, "firmware": firmware, "sdk": sdk})
        if model != profile["model"]:
            return bad(
                f"model {model}, profile is {profile['model']}",
                ["Pass the right --model or check the phone."],
            )
        if profile["firmware"] and firmware not in profile["firmware"]:
            expected = " or ".join(profile["firmware"])
            return bad(
                f"firmware {firmware}; the kit images are for {expected}",
                ["Flashing images built for other firmware causes boot loops. Get matching images first."],
            )
        return ok(f"{model} {firmware} sdk {sdk}")

    def oem_action(ctx: Any) -> None:
        sh(ctx, "settings put global development_settings_enabled 1; am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS")
        ctx.sleep(2500)
        if getprop(ctx, "sys.oem_unlock_allowed") == "1":
            return
        found = False
        for _ in range(4):
            found = tap_text(ctx, "OEM unlocking", tries=1)
            if found:
                break
            sh(ctx, "input swipe 500 1500 500 700 300")
        if not found:
            raise StepFailed(
                'no "OEM unlocking" item in Developer options',
                ["The phone has not checked in online (KnoxGuard) or is a carrier model."],
            )
        tap_text(ctx, ["Enable", "Turn on"])

    def bootloader_unlock_action(ctx: Any) -> None:
        reserve_reboot(ctx, "bootloader unlock + wipe")
        if adb_state(ctx) == "device":
            sh(ctx, "reboot -p")
        poll_until(ctx, lambda: not usb_present(ctx), timeout_ms=2 * MIN)
        unlock_lines = [line[0].upper() + line[1:] + "." for line in profile["buttons"]["unlock_confirm"]]
        human_step(
            ctx,
            title=f"unlock the bootloader on the {model_label}",
            lines=[
                *download_lines(profile, unlocked=False),
                *unlock_lines,
                'The phone wipes itself and restarts to the "Welcome" screen. Leave it there.',
            ],
            waiting="the phone to come back on USB after the wipe",
            timeout_ms=20 * MIN,
            instead=_wrong_combo_rows(profile),
            until=usb_watch(ctx, need_absence_first=True),
        )

    def kg_online_action(ctx: Any) -> None:
        if adb_state(ctx) == "device":
            ctx.wifi()
        else:
            human_step(
                ctx,
                title="join Wi-Fi on the Welcome screen (nothing else)",
                lines=[
                    "Tap Start, accept the terms, stop at the Wi-Fi screen.",
                    f'Join "{ctx.wifi_ssid()}" (passwords are never printed).',
                    "When it shows Connected, tap Next once and stay on the next screen.",
                    "Do NOT finish setup: it is wiped again after the flash.",
                ],
                waiting="you to confirm it shows Connected (press Enter here)",
                timeout_ms=20 * MIN,
                poll_ms=1000,
                instead=[("No Wi-Fi screen", "tap Back to the Welcome screen and start again")],
                until=lambda: ctx.confirm("Wi-Fi shows Connected? Press Enter"),
            )
        ctx.state["onlineSince"] = ctx.now()
        ctx.say("  holding 90 s online so KnoxGuard checks in")
        ctx.sleep(90_000)

    def download_mode_action(ctx: Any) -> None:
        reserve_reboot(ctx, "download mode")
        if adb_state(ctx) == "device":
            adb(ctx, ["reboot", "download"])
            if poll_until(ctx, lambda: in_download_mode(ctx), timeout_ms=90_000):
                return
        human_step(
            ctx,
            title="put the phone in download mode",
            lines=[
                'Hold the side key, tap "Power off" (skip if already off).',
                *download_lines(profile, unlocked=True),
            ],
            waiting="heimdall to see a phone in download mode",
            timeout_ms=10 * MIN,
            instead=[
                *[r for r in _wrong_combo_rows(profile) if not r[0].startswith("A green")],
                (
                    '"Device unlock mode" / relock question',
                    "you pressed Volume Up too long. Do NOT confirm; hold Volume Down + Power 7 s, start again",
                ),
            ],
            until=lambda: in_download_mode(ctx),
        )

    def flash_action(ctx: Any) -> None:
        sessions = (
            [[img] for img in profile["images"]]
            if profile["heimdall_sessions"] == "per-partition"
            else [profile["images"]]
        )
        ctx.state["flashLog"] = []
        for idx, images in enumerate(sessions):
            args: list[str] = ["flash"]
            for img in images:
                args.extend([f"--{img['partition']}", str(Path(ctx.kit) / img["file"])])
            args.append("--no-reboot")
            if idx > 0:
                args.append("--resume")
            res = ctx.run([ctx.heimdall, *args], timeout=10 * MIN)
            tail = (res.stdout + "\n" + res.stderr).strip().splitlines()[-6:]
            ctx.state["flashLog"].append({"code": res.returncode, "tail": tail})
            for img in images:
                part = img["partition"]
                if res.returncode != 0 or f"{part} upload successful".lower() not in res.stdout.lower():
                    raise StepFailed(
                        f"heimdall did not report {part} upload successful",
                        tail,
                    )
        ctx.state["flashedAt"] = ctx.now()

    def recovery_wipe_action(ctx: Any) -> None:
        reserve_reboot(ctx, "recovery wipe + first boot")
        try:
            human_step(
                ctx,
                title="go from download mode straight into recovery and wipe data",
                lines=_wipe_lines(profile, from_download=True),
                waiting="the phone to reach the Welcome screen (60 s steady on USB)",
                timeout_ms=15 * MIN,
                instead=[
                    ("Download screen stays", "this screen ignores recovery keys: do Volume Down + Power first"),
                    ("Phone boots to Welcome without the menu", "missed the menu: data from before the flash survives"),
                    ('"No command" robot', "hold Power, tap Volume Up once to show the menu"),
                ],
                until=usb_watch(ctx, need_absence_first=True, loop_after_ms=3 * MIN),
            )
        except BootLoop:
            boot_loop_rescue(ctx, profile)
        finally:
            ctx.release_download_lock()

    def setup_action(ctx: Any) -> None:
        for attempt in range(2):
            try:
                _setup_human(ctx)
                break
            except BootLoop:
                if attempt > 0:
                    raise StepFailed(
                        "still looping after a recovery wipe",
                        [
                            "The images may not match the firmware: check the identify step note.",
                            "Flash stock firmware with heimdall, then re-run --from download-mode.",
                        ],
                    )
                boot_loop_rescue(ctx, profile)
        ensure_silent(ctx)

    def root_boot_action(ctx: Any) -> None:
        reserve_reboot(ctx, "rooted boot")
        adb(ctx, ["reboot", "recovery"] if profile["rooted_boot"] == "recovery" else ["reboot"])
        ctx.sleep(10_000)
        back = poll_until(
            ctx,
            lambda: adb_state(ctx) == "device",
            timeout_ms=4 * MIN,
            poll_ms=5000,
        )
        if back:
            ensure_silent(ctx)
        else:
            raise StepFailed(
                "phone did not come back to adb after the rooted boot",
                [
                    'Stock recovery menu on screen = flash never committed (KnoxGuard). Reboot and re-run --from kg-online.',
                    "Logo, black, logo again = boot loop: re-run --from setup.",
                ],
            )

    def magisk_shell_action(ctx: Any) -> None:
        if not sh(ctx, "pm path com.topjohnwu.magisk")["out"]:
            adb(ctx, ["push", str(Path(ctx.kit) / "Magisk.apk"), "/data/local/tmp/magisk.apk"])
            sh(ctx, "pm install -r /data/local/tmp/magisk.apk; rm -f /data/local/tmp/magisk.apk")
        sh(ctx, "am start -n com.topjohnwu.magisk/.ui.MainActivity --es section superuser")
        ctx.sleep(3000)
        if (
            tap_text(ctx, "Grant Superuser")
            and tap_text(ctx, "Shell")
            and poll_until(ctx, lambda: _is_root(ctx), timeout_ms=15_000)
        ):
            return
        extra = (
            'Magisk app: accept "additional setup", choose Direct install, let it reboot.'
            if profile["root_method"] == "twrp"
            else 'Magisk is open on the Superuser tab. Ignore the "reflash" message.'
        )
        human_step(
            ctx,
            title="grant Shell root in Magisk (Magisk 31.1 has no su prompt)",
            lines=[extra, 'Tap "Grant Superuser" (or +), then "Shell".'],
            waiting="su -c id to return uid 0",
            timeout_ms=15 * MIN,
            instead=[("No Superuser tab", "the phone booted unrooted. Re-run --from root-boot")],
            until=lambda: _is_root(ctx),
        )

    def twrp_action(ctx: Any) -> None:
        reserve_reboot(ctx, "TWRP")
        human_step(
            ctx,
            title="go from download mode into TWRP",
            lines=[*_recovery_lines(profile, from_download=True), 'In TWRP, swipe "Allow modifications".'],
            waiting="adb to see TWRP (recovery state)",
            timeout_ms=15 * MIN,
            until=lambda: adb_state(ctx) == "recovery",
        )
        ctx.release_download_lock()
        backup = ctx.paths.state_dir / f"{ctx.serial}-boot-stock.img"
        sh(ctx, "dd if=/dev/block/by-name/boot of=/tmp/boot.img 2>/dev/null || dd if=$(ls /dev/block/platform/*/by-name/BOOT) of=/tmp/boot.img")
        adb(ctx, ["pull", "/tmp/boot.img", str(backup)])
        sh(ctx, "twrp format data")
        adb(ctx, ["push", str(Path(ctx.kit) / profile["magisk_zip"]), "/tmp/magisk.zip"])
        installed = sh(ctx, "twrp install /tmp/magisk.zip")
        if installed["code"] != 0:
            raise StepFailed("twrp install magisk.zip failed", installed["out"].splitlines()[-5:])
        adb(ctx, ["reboot"])
        ctx.state["flashedAt"] = ctx.now()

    def remote_access_action(ctx: Any) -> None:
        keys_file = ctx.authorized_keys()
        files = {
            "court-boot.sh": PHONE_SETUP_DIR / "court-boot.sh",
            "termux-ssh.sh": PHONE_SETUP_DIR / "termux-ssh.sh",
            "termux.apk": Path(ctx.kit) / "termux.apk",
            "adbkey.pub": Path(ctx.home) / ".android" / "adbkey.pub",
            "keys": keys_file,
        }
        for name, local in files.items():
            res = adb(ctx, ["push", str(local), f"/data/local/tmp/{name}"])
            if res.returncode != 0:
                raise StepFailed(f"push {name} failed", [str(local)])
        sh(
            ctx,
            'su -c "mkdir -p /data/adb/service.d; cp /data/local/tmp/court-boot.sh /data/adb/service.d/; '
            "chmod 755 /data/adb/service.d/court-boot.sh; "
            "grep -qFf /data/local/tmp/adbkey.pub /data/misc/adb/adb_keys 2>/dev/null || "
            'cat /data/local/tmp/adbkey.pub >> /data/misc/adb/adb_keys; chmod 644 /data/local/tmp/*"',
        )
        sh(ctx, "settings put global package_verifier_enable 0; settings put global verifier_verify_adb_installs 0")
        sh(ctx, "pm path com.termux >/dev/null || pm install -r /data/local/tmp/termux.apk; am start -n com.termux/.app.TermuxActivity")
        poll_until(
            ctx,
            lambda: sh(ctx, 'su -c "test -e /data/data/com.termux/files/usr/bin/pkg && echo Y"')["out"] == "Y",
            timeout_ms=4 * MIN,
        )
        uid = str(sh(ctx, 'su -c "stat -c %u /data/data/com.termux"')["out"])
        if not uid.isdigit() or len(uid) < 5:
            raise StepFailed(f'Termux uid "{uid}" invalid', ["Open Termux once on the phone and wait for bootstrap."])
        sh(ctx, f"su -c \"magisk --sqlite 'INSERT OR REPLACE INTO policies (uid,policy,until,logging,notification) VALUES({uid},2,0,1,0)'\"")
        sh(ctx, 'su -c "dumpsys deviceidle whitelist +com.termux; am set-standby-bucket com.termux active"')
        sh(ctx, f"su -c \"su -g {uid} -G 3003 -G 9997 {uid} -c 'sh /data/local/tmp/termux-ssh.sh'\"", timeout=10 * MIN)
        if getprop(ctx, "service.adb.tcp.port") != "5555":
            sh(ctx, 'su -c "/data/adb/magisk/busybox setsid sh /data/adb/service.d/court-boot.sh </dev/null >/dev/null 2>&1 &"')
            ctx.sleep(8000)
            ctx.run([getattr(ctx, "adb_bin", "adb"), "-s", ctx.serial, "wait-for-device"], timeout=60)

    def remote_access_verify(ctx: Any) -> dict[str, Any]:
        wlan_out = str(sh(ctx, "ip -4 -o addr show wlan0")["out"])
        import re

        ip_match = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", wlan_out)
        if not ip_match:
            return bad("no wlan0 address")
        ip = ip_match.group(1)
        ctx.state["lanIp"] = ip
        port_up = poll_until(
            ctx,
            lambda: ctx.run(["nc", "-z", "-G", "4", ip, "8022"]).returncode == 0,
            timeout_ms=2 * MIN,
            poll_ms=4000,
        )
        boot_ok = sh(ctx, 'su -c "test -x /data/adb/service.d/court-boot.sh && echo Y"')["out"] == "Y"
        if port_up and boot_ok:
            return ok(f"sshd {ip}:8022, court-boot.sh installed")
        return bad(f"sshd reachable={bool(port_up)} court-boot={boot_ok}")

    def tailscale_done(ctx: Any) -> str | None:
        if getattr(ctx.opts, "skip_tailscale", False):
            return "skipped (--skip-tailscale)"
        rollout = getattr(ctx.opts, "tailscale_rollout", None) or os.environ.get("HYDRACAM_TAILSCALE_ROLLOUT")
        if not rollout:
            return "no --tailscale-rollout configured; skipped"
        if ctx.run(["tailscale", "ip", "-4", ctx.name]).returncode == 0:
            return f"{ctx.name} on the tailnet"
        return None

    def tailscale_action(ctx: Any) -> None:
        rollout = getattr(ctx.opts, "tailscale_rollout", None) or os.environ.get("HYDRACAM_TAILSCALE_ROLLOUT")
        jump = getattr(ctx.opts, "jump_host", "") or ""
        res = ctx.run(
            ["env", f"COURT_JUMP_HOST={jump}", "bash", str(rollout), ctx.state.get("lanIp", ""), ctx.name],
            timeout=6 * MIN,
        )
        if res.returncode != 0:
            raise StepFailed("tailscale rollout failed", res.stderr.splitlines()[-5:])

    def tailscale_verify(ctx: Any) -> dict[str, Any]:
        if getattr(ctx.opts, "skip_tailscale", False) or not (
            getattr(ctx.opts, "tailscale_rollout", None) or os.environ.get("HYDRACAM_TAILSCALE_ROLLOUT")
        ):
            return ok("tailscale skipped")
        if ctx.run(["tailscale", "ip", "-4", ctx.name]).returncode == 0:
            return ok(f"{ctx.name} joined")
        return bad("not on the tailnet", ["Check tailscaled / authkey on phone."])

    def hardening_action(ctx: Any) -> None:
        sh(ctx, 'su -c "touch /data/adb/charge-cap.on"')
        if profile["charge_cap"] == "kernel":
            sh(ctx, 'su -c "echo 60 > /sys/class/power_supply/battery/batt_full_capacity"')
        else:
            cap_script = PHONE_SETUP_DIR / "charge-cap.sh"
            adb(ctx, ["push", str(cap_script), "/data/local/tmp/charge-cap.sh"])
            sh(ctx, 'su -c "cp /data/local/tmp/charge-cap.sh /data/adb/service.d/; chmod 755 /data/adb/service.d/charge-cap.sh"')
        if not ctx.state.get("deviceCareOff"):
            sh(ctx, "am start -n com.samsung.android.lool/com.samsung.android.sm.ui.dashboard.SmartManagerDashBoardActivity")
            human_step(
                ctx,
                title="turn off Device care automation",
                lines=[
                    "Device care is open. Tap the three dots > Automation.",
                    'Turn OFF "Auto restart at set times" and "Auto optimise daily".',
                    "Back here, press Enter.",
                ],
                waiting="Enter",
                timeout_ms=15 * MIN,
                poll_ms=1000,
                until=lambda: ctx.confirm("Both switches off? Press Enter"),
            )
            ctx.state["deviceCareOff"] = True

    def hardening_verify(ctx: Any) -> dict[str, Any]:
        marker = sh(ctx, 'su -c "test -f /data/adb/charge-cap.on && echo Y"')["out"] == "Y"
        if profile["charge_cap"] != "kernel":
            return ok("charge-cap.sh + marker") if marker else bad("no charge-cap marker")
        cap = sh(ctx, "cat /sys/class/power_supply/battery/batt_full_capacity")["out"]
        return ok("batt_full_capacity=60, marker set") if (marker and cap == "60") else bad(f"marker={marker} cap={cap}")

    def google_account_value(ctx: Any) -> str:
        return getattr(ctx.opts, "google_account", None) or os.environ.get("HYDRACAM_FLEET_GOOGLE_ACCOUNT", "")

    def google_done(ctx: Any) -> str | None:
        acct = google_account_value(ctx)
        if getattr(ctx.opts, "skip_google", False) or not acct:
            return "skipped (no --google-account configured)"
        has_acct = f"name={acct}, type=com.google" in str(sh(ctx, "dumpsys account")["out"])
        if has_acct and ctx.state.get("playAutoUpdateOff"):
            return "account present"
        return None

    def google_action(ctx: Any) -> None:
        acct = google_account_value(ctx)
        if not acct:
            return
        if f"name={acct}, type=com.google" not in str(sh(ctx, "dumpsys account")["out"]):
            sh(ctx, "am start -a android.settings.ADD_ACCOUNT_SETTINGS --esa account_types com.google")
            email = poll_until(
                ctx,
                lambda: "identifierId" in str((focused_node(ctx) or {}).get("resource-id", "")),
                timeout_ms=2 * MIN,
            )
            if not email:
                raise StepFailed("Google sign-in email field never had focus", ["Is the phone online?"])
            sh(ctx, f"input text {shlex.quote(acct)}; input keyevent 66")
            pw = poll_until(
                ctx,
                lambda: (focused_node(ctx) or {}).get("password") == "true",
                timeout_ms=2 * MIN,
            )
            if not pw:
                raise StepFailed("password field never had focus", ["Finish sign-in on phone and re-run."])
            service = getattr(ctx.opts, "google_keychain_service", "hydracam-fleet-google")
            secret = keychain(ctx, service, acct)
            type_secret(ctx, secret)
            del secret
            sh(ctx, "input keyevent 66")
            human_step(
                ctx,
                title="finish the Google sign-in screens",
                lines=["Accept the terms. Turn OFF backup if asked. Skip everything else."],
                waiting=f"{acct} in the account list",
                timeout_ms=15 * MIN,
                until=lambda: f"name={acct}, type=com.google" in str(sh(ctx, "dumpsys account")["out"]),
            )
        sh(ctx, "bmgr enable false; pm disable-user --user 0 com.google.android.apps.photos")
        if not ctx.state.get("playAutoUpdateOff"):
            sh(ctx, 'am start -a android.intent.action.VIEW -d "market://details?id=com.android.vending"')
            human_step(
                ctx,
                title="turn off Play Store auto-update",
                lines=['Play Store: profile > Settings > Network preferences > "Don\'t auto-update apps".', "Press Enter."],
                waiting="Enter",
                timeout_ms=15 * MIN,
                poll_ms=1000,
                until=lambda: ctx.confirm("Auto-update off? Press Enter"),
            )
            ctx.state["playAutoUpdateOff"] = True

    def google_verify(ctx: Any) -> dict[str, Any]:
        acct = google_account_value(ctx)
        if getattr(ctx.opts, "skip_google", False) or not acct:
            return ok("google account skipped")
        backup = str(sh(ctx, "bmgr enabled")["out"])
        photos_off = "com.google.android.apps.photos" in str(sh(ctx, "pm list packages -d")["out"]) or not sh(ctx, "pm path com.google.android.apps.photos")["out"]
        has_acct = f"name={acct}, type=com.google" in str(sh(ctx, "dumpsys account")["out"])
        return ok("account, backup disabled, Photos disabled") if (has_acct and "disabled" in backup and photos_off) else bad(f"account={has_acct}")

    def hydracam_action(ctx: Any) -> None:
        pkg = getattr(ctx.opts, "package", DEFAULT_COURT_PACKAGE)
        if not sh(ctx, f"pm path {shlex.quote(pkg)}")["out"]:
            apk = Path(ctx.opts.apk) if getattr(ctx.opts, "apk", None) else Path(ctx.kit) / "hydracam-court.apk"
            if not apk.exists():
                raise StepFailed(
                    f"missing {apk}",
                    ["Build with `flutter build apk --flavor court -t lib/court/main_court.dart` or pass --apk."],
                )
            adb(ctx, ["push", str(apk), "/data/local/tmp/hydracam-court.apk"])
            sh(ctx, "pm install -r -g /data/local/tmp/hydracam-court.apk; rm -f /data/local/tmp/hydracam-court.apk")
        for perm in ("android.permission.CAMERA", "android.permission.RECORD_AUDIO", "android.permission.POST_NOTIFICATIONS"):
            sh(ctx, f"pm grant {shlex.quote(pkg)} {perm}")
        grant_magisk_su(ctx, pkg)
        whitelist_background(ctx, pkg)
        ensure_silent(ctx)

    def hydracam_verify(ctx: Any) -> dict[str, Any]:
        pkg = getattr(ctx.opts, "package", DEFAULT_COURT_PACKAGE)
        uid = read_package_uid(ctx, pkg)
        return ok(f"{pkg} uid={uid}") if uid else bad(f"{pkg} not installed")

    def pin_action(ctx: Any) -> None:
        service = getattr(ctx.opts, "pin_keychain_service", "hydracam-court-screen-pin")
        account = getattr(ctx.opts, "pin_keychain_account", None) or ctx.serial
        pin = keychain(ctx, service, account)
        if not pin.isdigit() or not (4 <= len(pin) <= 16):
            raise StepFailed("Keychain PIN is not 4-16 digits", [])
        res = adb(
            ctx,
            ["shell", "su -c 'IFS= read -r p; locksettings set-pin \"$p\" >/dev/null 2>&1; c=$?; unset p; exit $c'"],
            input_text=f"{pin}\n",
        )
        del pin
        if res.returncode != 0:
            raise StepFailed("locksettings set-pin failed (output suppressed)", [])

    def k2_enroll_done(ctx: Any) -> str | None:
        if getattr(ctx.opts, "skip_k2", False):
            return "skipped (--skip-k2)"
        return None

    def k2_enroll_action(ctx: Any) -> None:
        if getattr(ctx.opts, "skip_k2", False):
            return
        if not getattr(ctx.opts, "court", None) or not getattr(ctx.opts, "slot", None):
            raise StepFailed(
                "--court and --slot are required for K2 Court Cloud enrollment",
                ["Pass --court <slug> --slot <slot>, or pass --skip-k2 to defer K2 registration."],
            )
        client = _make_k2_client(ctx)
        health = client.health()
        skew = health.get("contractSkew")
        if skew != "same":
            ctx.log(
                f"K2 contract skew: server={health.get('contractVersion')} local=1.29 ({skew})"
            )
        creds = load_creds_store(ctx.paths.creds_file)
        cached_entry = find_creds_entry(
            creds,
            serial=ctx.serial,
            host=ctx.name,
            device_id=ctx.state.get("deviceId"),
        )
        outcome = enroll_single_k2_device(
            client=client,
            court_slug=ctx.opts.court,
            slot=ctx.opts.slot,
            serial=ctx.serial,
            host=ctx.name,
            name=ctx.name,
            device_id=getattr(ctx.opts, "device_id", None),
            cached_device_id=ctx.state.get("deviceId")
            or (cached_entry.get("deviceId") if cached_entry else None),
            cached_secret=cached_entry.get("secret") if cached_entry else None,
            rotate_secret=bool(getattr(ctx.opts, "rotate_secret", False)),
        )
        pkg = getattr(ctx.opts, "package", DEFAULT_COURT_PACKAGE)
        grant_magisk_su(ctx, pkg)
        whitelist_background(ctx, pkg)
        push_k2_enrollment(ctx, outcome.enrollment, package_name=pkg)
        restart_court_app(ctx, package_name=pkg)
        upsert_creds_entry(
            ctx.paths.creds_file,
            enrollment=outcome.enrollment,
            serial=ctx.serial,
            host=ctx.name,
            port=ctx.port,
        )
        # Never store secret in enroll-state JSON; store only non-secret identity metadata.
        ctx.state["deviceId"] = outcome.enrollment.device_id
        ctx.state["courtId"] = outcome.enrollment.court_id
        ctx.state["courtSlug"] = outcome.enrollment.court_slug
        ctx.state["slot"] = outcome.enrollment.slot
        ctx.state["mountRev"] = outcome.enrollment.mount_rev
        save_state(ctx.paths, ctx.state)

    def k2_enroll_verify(ctx: Any) -> dict[str, Any]:
        if getattr(ctx.opts, "skip_k2", False):
            return ok("k2 enrollment skipped")
        dev_id = ctx.state.get("deviceId")
        if not dev_id:
            return bad("no deviceId recorded in state")
        client = _make_k2_client(ctx)
        record = _device_record_in_k2(client, dev_id)
        if not record or record.get("revoked"):
            return bad(f"device {dev_id} missing or revoked in K2")
        return ok(
            f"K2 {dev_id} court={ctx.state.get('courtSlug')}/{ctx.state.get('slot')} "
            f"mountRev={record.get('mountRev')} contract={record.get('contractVersion') or 'pending'}"
        )

    def reboot_test_action(ctx: Any) -> None:
        reserve_reboot(ctx, "reboot test")
        ctx.state["rebootTestBoot"] = str(sh(ctx, "cat /proc/sys/kernel/random/boot_id")["out"])
        sh(ctx, profile["reboot_command"])
        ctx.sleep(60_000)

    def reboot_test_verify(ctx: Any) -> dict[str, Any]:
        back = poll_until(ctx, lambda: adb_state(ctx) == "device" and _is_root(ctx), timeout_ms=4 * MIN, poll_ms=10_000)
        if not back:
            return bad("not reachable/rooted after reboot")
        ensure_silent(ctx)
        boot = str(sh(ctx, "cat /proc/sys/kernel/random/boot_id")["out"])
        if not boot or boot == ctx.state.get("rebootTestBoot"):
            return bad("boot id unchanged: the reboot did not happen")
        return ok("new boot, rooted, silent")

    common: dict[str, Step] = {
        "preflight": Step("preflight", "locks, name, kit, heimdall, reboot budget", verify=lambda c: c.preflight(), always=True),
        "identify": Step("identify", "model and firmware", pre=_need_device, verify=identify_verify),
        "oem-unlock": Step(
            "oem-unlock",
            "OEM unlocking toggle (remote, uiautomator)",
            pre=_need_device,
            done=lambda c: "bootloader already unlocked" if getprop(c, "ro.boot.flash.locked") == "0" else None,
            action=oem_action,
            verify=lambda c: ok("OEM unlocking on")
            if getprop(c, "ro.boot.flash.locked") == "0" or getprop(c, "sys.oem_unlock_allowed") == "1"
            else bad("sys.oem_unlock_allowed is not 1"),
        ),
        "bootloader-unlock": Step(
            "bootloader-unlock",
            "bootloader unlock (WIPES the phone)",
            done=lambda c: "ro.boot.flash.locked=0"
            if adb_state(c) == "device" and getprop(c, "ro.boot.flash.locked") == "0"
            else None,
            action=bootloader_unlock_action,
            verify=lambda _c: ok("phone back on USB after the wipe"),
        ),
        "kg-online": Step(
            "kg-online",
            "online at least 90 s before flashing (KnoxGuard)",
            action=kg_online_action,
            verify=lambda c: ok("online >= 90 s")
            if c.now() - c.state.get("onlineSince", c.now()) >= 90_000
            else bad("online for less than 90 s"),
        ),
        "download-mode": Step(
            "download-mode",
            "download mode (one phone at a time)",
            pre=lambda c: bad(
                "another phone is already in download mode",
                ["heimdall cannot tell phones apart. Wait until it leaves."],
            )
            if in_download_mode(c)
            else (c.take_download_lock() or ok("no other phone in download mode")),
            action=download_mode_action,
            verify=lambda c: ok("heimdall detect: download mode")
            if in_download_mode(c)
            else bad("not in download mode"),
        ),
        "flash": Step(
            "flash",
            f"heimdall flash {' + '.join(i['partition'] for i in profile['images'])} --no-reboot",
            pre=lambda c: ok("download mode")
            if in_download_mode(c)
            else bad("not in download mode", ["Re-run --from download-mode."]),
            action=flash_action,
            verify=lambda c: ok("upload successful (commit proven at root-boot)")
            if c.state.get("flashedAt")
            else bad("no flash recorded"),
        ),
        "recovery-wipe": Step(
            "recovery-wipe",
            "wipe data in recovery BEFORE the first boot of the new images",
            action=recovery_wipe_action,
            verify=lambda _c: ok("wiped; phone steady at Welcome"),
        ),
        "twrp-root": Step(
            "twrp-root",
            "TWRP: back up BOOT, format data, install Magisk",
            action=twrp_action,
            verify=lambda c: ok("boot backed up, Magisk installed")
            if (c.paths.state_dir / f"{c.serial}-boot-stock.img").exists()
            else bad("no boot backup"),
        ),
        "setup": Step(
            "setup",
            "the ONE human setup (minimal) + USB debugging",
            done=lambda c: "adb already authorized" if adb_state(c) == "device" else None,
            action=setup_action,
            verify=lambda c: ok("adb authorized") if adb_state(c) == "device" else bad("adb not authorized"),
        ),
        "verify-unlock": Step(
            "verify-unlock",
            "bootloader unlocked, orange state",
            pre=_need_device,
            verify=lambda c: ok("flash.locked=0 orange")
            if getprop(c, "ro.boot.flash.locked") == "0" and getprop(c, "ro.boot.verifiedbootstate") == "orange"
            else bad(
                f"flash.locked={getprop(c, 'ro.boot.flash.locked')} "
                f"verifiedbootstate={getprop(c, 'ro.boot.verifiedbootstate')}",
                ["Re-run --from bootloader-unlock."],
            ),
        ),
        "wifi": Step(
            "wifi",
            "Wi-Fi from local wifi.tsv, internet check",
            pre=_need_device,
            done=lambda c: "already online" if _internet(c) else None,
            action=lambda c: c.wifi(),
            verify=lambda c: ok("ping 8.8.8.8 and DNS ok")
            if _internet(c)
            else bad("no internet", ["Check the router; the phone is on Wi-Fi without internet."]),
        ),
        "root-boot": Step(
            "root-boot",
            "adb reboot recovery over USB = rooted boot (~50 s)"
            if profile["rooted_boot"] == "recovery"
            else "Magisk boot",
            pre=_need_device,
            done=lambda c: "magiskd running" if _magiskd_running(c) else None,
            action=root_boot_action,
            verify=lambda c: ok("magiskd running")
            if _magiskd_running(c)
            else bad("no magiskd after boot"),
        ),
        "magisk-shell": Step(
            "magisk-shell",
            "Magisk app + Shell superuser grant",
            pre=_need_device,
            done=lambda c: "su -c id = uid 0" if _is_root(c) else None,
            action=magisk_shell_action,
            verify=lambda c: ok("uid 0") if _is_root(c) else bad("su denied"),
        ),
        "remote-access": Step(
            "remote-access",
            "Termux sshd, court-boot.sh, this Mac's adb key",
            pre=lambda c: ok("root") if _is_root(c) else bad("no root"),
            done=lambda c: "skipped (--skip-remote-access)"
            if getattr(c.opts, "skip_remote_access", False)
            else None,
            action=remote_access_action,
            verify=lambda c: ok("remote-access skipped")
            if getattr(c.opts, "skip_remote_access", False)
            else remote_access_verify(c),
        ),
        "tailscale": Step(
            "tailscale",
            "Tailscale rollout (optional)",
            done=tailscale_done,
            action=tailscale_action,
            verify=tailscale_verify,
        ),
        "hardening": Step(
            "hardening",
            "charge cap, Device care auto-restart/optimise off",
            pre=_need_device,
            action=hardening_action,
            verify=hardening_verify,
        ),
        "google-account": Step(
            "google-account",
            "optional fleet Google account, backup off, Play auto-update off, Photos off",
            pre=_need_device,
            done=google_done,
            action=google_action,
            verify=google_verify,
        ),
        "hydracam": Step(
            "hydracam",
            "HydraCam court app install, permissions, Magisk su, freecess whitelist",
            pre=_need_device,
            action=hydracam_action,
            verify=hydracam_verify,
        ),
        "pin-lock": Step(
            "pin-lock",
            "PIN lock (Keychain, stdin only)",
            pre=_need_device,
            done=lambda c: "skipped (--skip-pin)"
            if getattr(c.opts, "skip_pin", False)
            else ("secure lock already set" if "secure=true" in str(sh(c, "dumpsys trust")["out"]) else None),
            action=pin_action,
            verify=lambda c: ok("pin-lock skipped")
            if getattr(c.opts, "skip_pin", False)
            else (ok("secure lock set") if "secure=true" in str(sh(c, "dumpsys trust")["out"]) else bad("no secure lock")),
        ),
        "k2-enroll": Step(
            "k2-enroll",
            "K2 Court Cloud single-device record + CourtEnrollReceiver (C1 1.29)",
            pre=_need_device,
            done=k2_enroll_done,
            action=k2_enroll_action,
            verify=k2_enroll_verify,
        ),
        "reboot-test": Step(
            "reboot-test",
            f"reboot test ({profile['reboot_command']}) -> rooted + silent",
            action=reboot_test_action,
            verify=reboot_test_verify,
        ),
    }

    root_steps = {
        "magisk-recovery": [common["root-boot"], common["magisk-shell"]],
        "magisk-boot": [common["root-boot"], common["magisk-shell"]],
        "twrp": [common["magisk-shell"]],
    }[profile["root_method"]]
    unlock = (
        [common["bootloader-unlock"], common["kg-online"]]
        if profile["bootloader_unlock"] == "blue-screen"
        else []
    )
    flash_and_wipe = (
        [common["download-mode"], common["flash"], common["twrp-root"]]
        if profile["root_method"] == "twrp"
        else [common["download-mode"], common["flash"], common["recovery-wipe"]]
    )
    return [
        common["preflight"],
        common["identify"],
        common["oem-unlock"],
        *unlock,
        *flash_and_wipe,
        common["setup"],
        common["verify-unlock"],
        common["wifi"],
        *root_steps,
        common["remote-access"],
        common["tailscale"],
        common["hardening"],
        common["google-account"],
        common["hydracam"],
        common["pin-lock"],
        common["k2-enroll"],
        common["reboot-test"],
    ]
