#!/usr/bin/env python3
"""Unit tests for the ported court phone setup & enrollment CLI/engine/steps.

adb, heimdall, ioreg, security, and K2 HTTP requests are mocked; nothing touches
a physical or networked phone.
"""

from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import court_phone_setup as setup_cli  # noqa: E402
from hydracam_lib import court_enroll_engine as engine  # noqa: E402
from hydracam_lib import court_enroll_steps as steps_mod  # noqa: E402
from hydracam_lib import court_phone_device as device_mod  # noqa: E402
from hydracam_lib import court_profiles as profiles  # noqa: E402
from hydracam_lib.proc import CommandResult  # noqa: E402
from test_court_k2_enroll import FakeK2Server  # noqa: E402

SERIAL = "RTESTSERIAL1"
PIN = "83920571"
WIFI_PASSWORD = "correct-horse-battery"
GOOGLE_PASSWORD = "g00gle-Secret-pass"


class FakePhoneWorld:
    def __init__(self) -> None:
        self.adb: str | None = "device"
        self.usb: int | None = 26720
        self.boot_id = "boot-a"
        self.download_mode = False
        self.silent = True
        self.secure = False
        self.online = False
        self.installed_pkgs: set[str] = {"com.amaia23.hydracam.court"}
        self.props: dict[str, str] = {
            "ro.product.model": "SM-G970F",
            "ro.build.version.sdk": "31",
            "ro.boot.flash.locked": "0",
            "ro.boot.verifiedbootstate": "orange",
            "ro.serialno": SERIAL,
        }
        self.calls: list[list[str]] = []
        self.inputs: list[str] = []
        self.shell: list[str] = []
        self.pushed: dict[str, str] = {}
        self.on_tick = None

    def run(
        self,
        command: list[str],
        *,
        timeout: int = 60,
        input_text: str | None = None,
    ) -> CommandResult:
        del timeout
        self.calls.append(list(command))
        if input_text is not None:
            self.inputs.append(input_text)
        cmd0 = command[0]
        base0 = Path(cmd0).name

        if base0 == "adb" and command[1:3] == ["devices", "-l"]:
            row = f"{SERIAL}\t{self.adb} model:SM_G970F\n" if self.adb else ""
            return CommandResult(0, f"List of devices attached\n{row}", "")
        if base0 == "adb" and command[1:] == ["devices"]:
            row = f"{SERIAL}\t{self.adb}\n" if self.adb else ""
            return CommandResult(0, f"List of devices attached\n{row}", "")
        if cmd0 == "ioreg":
            if self.usb is None:
                return CommandResult(0, "+-o Root\n", "")
            return CommandResult(
                0,
                f'+-o Root\n+-o SAMSUNG_Android@1\n  "idProduct" = {self.usb}\n  "USB Serial Number" = "{SERIAL}"\n',
                "",
            )
        if base0.startswith("heimdall"):
            if len(command) > 1 and command[1] == "detect":
                return CommandResult(0 if self.download_mode else 1, "", "")
            if len(command) > 1 and command[1] == "flash":
                parts = [
                    arg[2:]
                    for arg in command
                    if arg.startswith("--") and arg[2:].isupper()
                ]
                return CommandResult(
                    0,
                    "\n".join(f"Uploading {p}\n100%\n{p} upload successful" for p in parts),
                    "",
                )
            return CommandResult(0, "v2.2.2", "")
        if cmd0 == "security":
            svc = command[command.index("-s") + 1]
            val = PIN if "pin" in svc else GOOGLE_PASSWORD
            return CommandResult(0, f"{val}\n", "")
        if base0 == "adb" and len(command) > 3 and command[3] == "shell":
            shell_cmd = command[4]
            self.shell.append(shell_cmd)
            if shell_cmd.startswith("getprop "):
                return CommandResult(0, self.props.get(shell_cmd[8:], ""), "")
            if "random/boot_id" in shell_cmd:
                return CommandResult(0, self.boot_id, "")
            if shell_cmd.startswith('echo "@haptic'):
                v = 0 if self.silent else 7
                return CommandResult(
                    0,
                    f"@haptic {0 if self.silent else 1}\n@zen {2 if self.silent else 0}\n"
                    f"@vol3 volume is {v} in range [0..15]\n@vol2 volume is {v} in range [0..15]\n",
                    "",
                )
            if "dumpsys trust" in shell_cmd:
                return CommandResult(0, "secure=true" if self.secure else "secure=false", "")
            if shell_cmd.startswith("sh /data/local/tmp/.enroll-wifi.sh"):
                return CommandResult(0, "WIFI_OK", "")
            if "ping -c 1" in shell_cmd:
                return CommandResult(0, "NET_OK" if self.online else "", "")
            if shell_cmd.startswith("pm path "):
                pkg = shell_cmd.split()[2]
                return CommandResult(
                    0,
                    f"package:/data/app/{pkg}.apk\n" if pkg in self.installed_pkgs else "",
                    "",
                )
            if "pm install " in shell_cmd:
                self.installed_pkgs.add("com.amaia23.hydracam.court")
                return CommandResult(0, "Success\n", "")
            if shell_cmd.startswith("dumpsys package "):
                return CommandResult(
                    0,
                    "    userId=10250\n"
                    if "com.amaia23.hydracam.court" in self.installed_pkgs
                    else "",
                    "",
                )
            if shell_cmd == "su" and input_text and "CourtEnrollReceiver" in input_text:
                return CommandResult(0, 'Broadcast completed: result=-1, data="ok"\n', "")
            if "su -c id" in shell_cmd or 'su -c "id -u"' in shell_cmd:
                return CommandResult(0, "uid=0(root)\n", "")
            return CommandResult(0, "", "")
        if base0 == "adb" and len(command) > 3 and command[3] == "push":
            if Path(command[4]).exists():
                self.pushed[command[5]] = Path(command[4]).read_text(
                    encoding="utf-8", errors="replace"
                )
            return CommandResult(0, "1 file pushed", "")
        return CommandResult(0, "", "")


def make_fake_ctx(world: FakePhoneWorld, tmp_dir: Path, **extra):
    clock = [1793793600000]  # 2026-11-04T12:00:00Z
    out: list[str] = []

    def sleep_fn(ms: int) -> None:
        clock[0] += ms
        if world.on_tick is not None:
            world.on_tick(clock[0])

    paths = engine.EnrollPaths(
        state_dir=tmp_dir / "state",
        lock_dir=tmp_dir / "locks",
        budget_dir=tmp_dir,
        creds_file=tmp_dir / "court-devices.json",
    )
    opts = setup_cli.parse_args(
        [
            SERIAL,
            "--name",
            "court-s10e-4",
            "--k2",
            "https://app.kvisor.com",
            "--court",
            "airport-squash-2",
            "--slot",
            "left",
        ]
    )
    ctx = setup_cli.SetupContext(
        serial=SERIAL,
        home=tmp_dir,
        opts=opts,
        paths=paths,
        state={"serial": SERIAL, "steps": {}},
        profile=profiles.profile_for("SM-G970F"),
        kit=tmp_dir / "kit",
        heimdall="heimdall",
        owner="court_phone_setup:test",
        reboot_cap=20,
        now=lambda: clock[0],
        sleep=sleep_fn,
        say=out.append,
        log=out.append,
        run=world.run,
        confirm=lambda _prompt: True,
        out=out,
    )
    for k, v in extra.items():
        setattr(ctx, k, v)
    return ctx, clock


class EngineAndGuardsTests(unittest.TestCase):
    def test_resume_skips_verified_and_from_reruns_later_steps(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            ctx, _ = make_fake_ctx(world, Path(tmp))
            ctx.state["steps"]["a"] = {"status": "verified", "at": "earlier"}
            ran: list[str] = []
            steps = [
                steps_mod.Step(
                    id="a",
                    title="a",
                    action=lambda _c: ran.append("a"),
                    verify=lambda _c: steps_mod.ok("ok"),
                ),
                steps_mod.Step(
                    id="b",
                    title="b",
                    action=lambda _c: ran.append("b"),
                    verify=lambda _c: steps_mod.ok("ok"),
                ),
            ]
            result = engine.run_steps(ctx, steps)
            self.assertEqual(result, {"ok": True})
            self.assertEqual(ran, ["b"])
            self.assertIn("a: skip", "\n".join(ctx.out))
            saved = json.loads((ctx.paths.state_dir / f"{SERIAL}.json").read_text())
            self.assertEqual(saved["steps"]["b"]["status"], "verified")

            ran.clear()
            for sid in ("a", "b", "c"):
                ctx.state["steps"][sid] = {"status": "verified", "at": "earlier"}
            steps3 = [
                steps_mod.Step(
                    id=sid,
                    title=sid,
                    action=lambda _c, s=sid: ran.append(s),
                    verify=lambda _c: steps_mod.ok("ok"),
                )
                for sid in ("a", "b", "c")
            ]
            engine.run_steps(ctx, steps3, from_step="b")
            self.assertEqual(ran, ["b", "c"])

    def test_failed_verify_stops_and_never_stores_secret_in_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            ctx, _ = make_fake_ctx(world, Path(tmp))
            ctx.state["secret"] = "should-be-stripped"
            ran: list[str] = []
            steps = [
                steps_mod.Step(
                    id="a",
                    title="a",
                    action=lambda _c: ran.append("a"),
                    verify=lambda _c: steps_mod.bad(
                        "magiskd absent", ["re-run --from root-boot"]
                    ),
                ),
                steps_mod.Step(
                    id="b",
                    title="b",
                    action=lambda _c: ran.append("b"),
                    verify=lambda _c: steps_mod.ok("ok"),
                ),
            ]
            result = engine.run_steps(ctx, steps)
            self.assertEqual(result, {"ok": False, "failedAt": "a"})
            self.assertEqual(ran, ["a"])
            state_file = ctx.paths.state_dir / f"{SERIAL}.json"
            self.assertEqual(stat.S_IMODE(state_file.stat().st_mode), 0o600)
            self.assertNotIn("should-be-stripped", state_file.read_text())
            self.assertIn("re-run --from root-boot", "\n".join(ctx.out))

    def test_reboot_budget_appends_and_refuses_past_cap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            ctx, _ = make_fake_ctx(world, Path(tmp), reboot_cap=2)
            engine.reserve_reboot(ctx, "one")
            engine.reserve_reboot(ctx, "two")
            bfile = engine.budget_file(ctx.paths.budget_dir, ctx.now())
            self.assertEqual(len(bfile.read_text().strip().splitlines()), 2)
            with self.assertRaisesRegex(engine.StepFailed, "reboot budget exhausted: 2/2"):
                engine.reserve_reboot(ctx, "three")

            ctx.state["steps"] = {}
            world.calls.clear()
            root_boot = next(
                s for s in steps_mod.build_steps(ctx.profile) if s.id == "root-boot"
            )
            result = engine.run_steps(ctx, [root_boot])
            self.assertEqual(result["failedAt"], "root-boot")
            self.assertFalse(any("reboot" in c for c in world.calls))

    def test_device_lock_reentry_and_stale_pid_takeover(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            lock_dir = Path(tmp)
            release = engine.acquire_lock(lock_dir, SERIAL, "thread-fleet-enroll")
            with self.assertRaises(engine.StepFailed):
                engine.acquire_lock(lock_dir, SERIAL, "court_phone_setup:999")
            engine.acquire_lock(lock_dir, SERIAL, "thread-fleet-enroll")
            release()
            self.assertFalse((lock_dir / SERIAL).exists())

            dead_lock = lock_dir / SERIAL
            dead_lock.mkdir(parents=True)
            (dead_lock / "owner").write_text(
                "court_phone_setup:999999\tpid=999999\thost=test\t2026-11-04T00:00:00Z\n"
            )
            rel2 = engine.acquire_lock(lock_dir, SERIAL, "court_phone_setup:1")
            rel2()


class DeviceHelpersAndSecretsTests(unittest.TestCase):
    def test_silence_once_per_boot_and_loud_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            ctx, _ = make_fake_ctx(world, Path(tmp))
            self.assertTrue(device_mod.ensure_silent(ctx))
            self.assertFalse(device_mod.ensure_silent(ctx))
            world.boot_id = "boot-b"
            self.assertTrue(device_mod.ensure_silent(ctx))
            self.assertEqual(sum("zen_mode 2" in c for c in world.shell), 2)

            loud_world = FakePhoneWorld()
            loud_world.silent = False
            loud_ctx, _ = make_fake_ctx(loud_world, Path(tmp))
            with self.assertRaisesRegex(engine.StepFailed, "not silent after boot"):
                device_mod.ensure_silent(loud_ctx)

    def test_wifi_password_pushed_0600_only_and_placeholders_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            world.online = True
            wifi_file = Path(tmp) / "wifi.tsv"
            wifi_file.write_text(f"HomeNet\t{WIFI_PASSWORD}\n", encoding="utf-8")
            ctx, _ = make_fake_ctx(world, Path(tmp), wifi_file=wifi_file)
            steps_mod.add_wifi(ctx)
            self.assertNotIn(WIFI_PASSWORD, json.dumps(world.calls))
            self.assertNotIn(WIFI_PASSWORD, "\n".join(ctx.out))
            self.assertIn(WIFI_PASSWORD, world.pushed["/data/local/tmp/.enroll-wifi.sh"])
            self.assertTrue(
                any("rm -f /data/local/tmp/.enroll-wifi.sh" in c for c in world.shell)
            )

            # Supports @keychain:SERVICE lookup when resolving TSV rows.
            rows = device_mod.parse_wifi_tsv(
                "Hotspot\t@keychain:court-fleet-hotspot\tmetered,fallback\n",
                keychain_lookup=lambda svc, acct: f"{svc}:{acct}:secret123",
            )
            self.assertEqual(rows[0]["password"], "court-fleet-hotspot:Hotspot:secret123")

            for bad in ("<password>", "PASSWORD", "***", ""):
                with self.assertRaisesRegex(engine.StepFailed, "no real password"):
                    device_mod.wifi_script([{"ssid": "HomeNet", "password": bad}], "HomeNet", 31)

    def test_pin_over_stdin_only_and_no_hardcoded_serial_for_pin(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            ctx, _ = make_fake_ctx(world, Path(tmp))
            pin_step = next(
                s for s in steps_mod.build_steps(ctx.profile) if s.id == "pin-lock"
            )
            pin_step.action(ctx)
            self.assertNotIn(PIN, json.dumps(world.calls))
            self.assertNotIn(PIN, "\n".join(ctx.out))
            self.assertEqual(world.inputs, [f"{PIN}\n"])
            sec_call = next(c for c in world.calls if c[0] == "security")
            self.assertIn(SERIAL, sec_call)
            self.assertNotIn("RF8RA1C0ZKB", json.dumps(world.calls))

    def test_google_account_skipped_by_default_and_focus_guarded_when_configured(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            ctx, _ = make_fake_ctx(world, Path(tmp))
            g_step = next(
                s for s in steps_mod.build_steps(ctx.profile) if s.id == "google-account"
            )
            # Without --google-account it skips cleanly without hardcoded emails.
            self.assertIn("skipped", g_step.done(ctx) or "")

            # When configured, waits for password field focus before typing secret.
            ctx.opts.google_account = "fleet-ops@example.com"
            ctx.state["playAutoUpdateOff"] = True
            focus = ["identifierId"]
            accounts = [""]
            base_run = world.run

            def custom_run(command, *, timeout=60, input_text=None):
                cmd = command[4] if len(command) > 4 and command[3] == "shell" else ""
                if cmd.startswith("uiautomator dump"):
                    world.calls.append(list(command))
                    xml = (
                        '<node resource-id="identifierId" focused="true" bounds="[0,0][10,10]"/>'
                        if focus[0] == "identifierId"
                        else '<node resource-id="password" password="true" focused="true" bounds="[0,0][10,10]"/>'
                    )
                    return CommandResult(0, xml, "")
                if cmd.startswith("input text fleet-ops"):
                    focus[0] = "password"
                if ".enroll-input" in cmd:
                    accounts[0] = "name=fleet-ops@example.com, type=com.google"
                if cmd == "dumpsys account":
                    return CommandResult(0, accounts[0], "")
                if cmd == "bmgr enabled":
                    return CommandResult(0, "Backup Manager currently disabled", "")
                return base_run(command, timeout=timeout, input_text=input_text)

            world.run = custom_run
            ctx.run = custom_run
            result = engine.run_steps(ctx, [g_step])
            self.assertTrue(result["ok"])
            self.assertNotIn(GOOGLE_PASSWORD, json.dumps(world.calls))
            self.assertNotIn(GOOGLE_PASSWORD, "\n".join(ctx.out))
            self.assertEqual(world.pushed["/data/local/tmp/.enroll-input"], GOOGLE_PASSWORD)


class BootLoopAndProfilesTests(unittest.TestCase):
    def test_usb_watch_boot_loop_rescue_and_human_step_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            world.usb = None
            ctx, clock = make_fake_ctx(world, Path(tmp))
            watch = steps_mod.usb_watch(ctx, loop_after_ms=180_000)
            self.assertFalse(watch())
            clock[0] += 181_000
            with self.assertRaises(steps_mod.BootLoop):
                watch()

            # Download mode product 0x685D (26717) never counts as Android.
            world.usb = 26717
            steady = steps_mod.usb_watch(ctx, stable_ms=60_000)
            self.assertFalse(steady())
            clock[0] += 61_000
            self.assertFalse(steady())
            world.usb = 26720
            self.assertFalse(steady())
            clock[0] += 61_000
            self.assertTrue(steady())

            # Full boot-loop rescue during setup budgets the wipe boot and resumes.
            world2 = FakePhoneWorld()
            world2.adb = None
            world2.usb = None
            ctx2, _ = make_fake_ctx(world2, Path(tmp) / "loop")
            wipe_shown_at = [None]

            def on_tick(now_ms: int) -> None:
                if wipe_shown_at[0] is None and "Wipe data/factory reset" in "\n".join(ctx2.out):
                    wipe_shown_at[0] = now_ms
                if wipe_shown_at[0] is not None and now_ms - wipe_shown_at[0] > 30_000:
                    world2.usb = 26720
                if wipe_shown_at[0] is not None and now_ms - wipe_shown_at[0] > 200_000:
                    world2.adb = "device"

            world2.on_tick = on_tick
            setup_step = next(s for s in steps_mod.build_steps(ctx2.profile) if s.id == "setup")
            res = engine.run_steps(ctx2, [setup_step])
            self.assertEqual(res, {"ok": True})
            output = "\n".join(ctx2.out)
            self.assertIn("BOOT LOOP suspected", output)
            self.assertIn("Volume Up + Bixby + Power", output)

            # Human step timeout prints "What you might see instead".
            world3 = FakePhoneWorld()
            world3.download_mode = False
            world3.adb = None
            world3.usb = None
            ctx3, _ = make_fake_ctx(world3, Path(tmp) / "timeout")
            dm_step = next(s for s in steps_mod.build_steps(ctx3.profile) if s.id == "download-mode")
            res3 = engine.run_steps(ctx3, [dm_step])
            self.assertEqual(res3["failedAt"], "download-mode")
            self.assertIn("What you might see instead", "\n".join(ctx3.out))
            self.assertIn("Device unlock mode", "\n".join(ctx3.out))

    def test_profiles_and_s10e_step_ordering_aligned_with_k2(self) -> None:
        for model, profile in profiles.PROFILES.items():
            for key in (
                "label",
                "chipset",
                "root_method",
                "images",
                "reboot_command",
                "charge_cap",
                "buttons",
            ):
                self.assertTrue(profile.get(key), f"{model} missing {key}")
            self.assertGreater(len(steps_mod.build_steps(profiles.profile_for(model))), 15)

        self.assertEqual(
            [m for m, p in profiles.PROFILES.items() if p["tested"]],
            ["SM-G970F"],
        )

        ids = [s.id for s in steps_mod.build_steps(profiles.profile_for("SM-G970F"))]
        self.assertLess(ids.index("bootloader-unlock"), ids.index("kg-online"))
        self.assertLess(ids.index("kg-online"), ids.index("download-mode"))
        self.assertLess(ids.index("flash"), ids.index("recovery-wipe"))
        self.assertLess(ids.index("recovery-wipe"), ids.index("setup"))
        self.assertLess(ids.index("setup"), ids.index("wifi"))
        self.assertLess(ids.index("wifi"), ids.index("root-boot"))
        self.assertIn("k2-enroll", ids)
        self.assertEqual(ids[-1], "reboot-test")

        s10e_lines = "\n".join(
            steps_mod.download_lines(profiles.profile_for("SM-G970F"), unlocked=False)
        )
        self.assertIn("Volume Down + Bixby", s10e_lines)
        self.assertNotIn("Volume Up + Volume Down", s10e_lines)

    def test_g781b_flashes_one_partition_per_heimdall_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            world.download_mode = True
            ctx, _ = make_fake_ctx(
                world, Path(tmp), profile=profiles.profile_for("SM-G781B")
            )
            flash = next(s for s in steps_mod.build_steps(ctx.profile) if s.id == "flash")
            result = engine.run_steps(ctx, [flash])
            self.assertTrue(result["ok"])
            sessions = [
                c for c in world.calls if len(c) > 1 and c[0] == "heimdall" and c[1] == "flash"
            ]
            self.assertEqual(len(sessions), 2)
            self.assertIn("--resume", sessions[1])
            self.assertTrue(all("--no-reboot" in c for c in sessions))

    def test_download_mode_refused_while_another_phone_is_in_download_mode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            world.download_mode = True
            ctx, _ = make_fake_ctx(world, Path(tmp))
            step = next(
                s for s in steps_mod.build_steps(ctx.profile) if s.id == "download-mode"
            )
            result = engine.run_steps(ctx, [step])
            self.assertEqual(result["failedAt"], "download-mode")
            self.assertIn("another phone is already in download mode", "\n".join(ctx.out))

    def test_hydracam_and_k2_enroll_steps_are_idempotent_with_single_k2_record(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            apk = tmp_dir / "hydracam-court.apk"
            apk.write_bytes(b"fake-court-apk")

            server = FakeK2Server()
            world = FakePhoneWorld()
            world.installed_pkgs.clear()
            ctx, _ = make_fake_ctx(world, tmp_dir, k2_transport=server.transport)
            ctx.opts.apk = apk
            ctx.admin_token = server.admin_token

            hydra_step = next(
                s for s in steps_mod.build_steps(ctx.profile) if s.id == "hydracam"
            )
            self.assertTrue(engine.run_steps(ctx, [hydra_step])["ok"])
            self.assertIn("com.amaia23.hydracam.court", world.installed_pkgs)
            self.assertTrue(
                any("magisk --sqlite 'INSERT" in c for c in world.shell)
            )
            self.assertTrue(
                any("deviceidle whitelist +com.amaia23.hydracam.court" in c for c in world.shell)
            )

            k2_step = next(
                s for s in steps_mod.build_steps(ctx.profile) if s.id == "k2-enroll"
            )
            self.assertTrue(engine.run_steps(ctx, [k2_step])["ok"])
            self.assertEqual(len(server.devices), 1)
            device_id = next(iter(server.devices))
            self.assertEqual(ctx.state["deviceId"], device_id)
            self.assertNotIn("secret", ctx.state)

            # Re-running k2-enroll (--from k2-enroll) reuses the exact same K2 record.
            self.assertTrue(engine.run_steps(ctx, [k2_step], from_step="k2-enroll")["ok"])
            self.assertEqual(len(server.devices), 1)
            self.assertEqual(server.devices[device_id]["mountRev"], 1)

            for mod_path in (
                Path(__file__).resolve().parent / "hydracam_lib" / "court_enroll_steps.py",
                Path(__file__).resolve().parent / "court_phone_setup.py",
            ):
                text = mod_path.read_text(encoding="utf-8")
                self.assertNotIn("keobfleet@gmail.com", text)
                self.assertNotIn("RF8RA1C0ZKB", text)
                self.assertNotIn("hydracam-spike-preview", text)
                self.assertNotIn("/api/fleet/devices", text)


class SetupCliTests(unittest.TestCase):
    def test_cli_validation_untested_refusal_status_and_preflight_lock_release(
        self,
    ) -> None:
        args = setup_cli.parse_args(
            [
                SERIAL,
                "--name",
                "court-s10e-4",
                "--port",
                "15562",
                "--from",
                "wifi",
                "--k2",
                "https://app.kvisor.com",
                "--court",
                "airport-squash-2",
                "--slot",
                "left",
            ]
        )
        self.assertEqual(args.serial, SERIAL)
        self.assertEqual(args.name, "court-s10e-4")
        self.assertEqual(args.port, 15562)
        self.assertEqual(args.from_step, "wifi")

        with self.assertRaises(ValueError):
            setup_cli.parse_args([SERIAL, "--name", "S10e 4"])
        with self.assertRaises(ValueError):
            setup_cli.parse_args([SERIAL, "--port", "abc"])

        with tempfile.TemporaryDirectory() as tmp:
            world = FakePhoneWorld()
            world.props["ro.product.model"] = "SM-G781B"
            out: list[str] = []
            rc = setup_cli.main(
                [SERIAL, "--adb", "adb", "--name", "court-s20fe-9"],
                home=Path(tmp),
                run=world.run,
                say=out.append,
                log=lambda _l: None,
            )
            self.assertEqual(rc, 2)
            self.assertIn("--allow-untested", "\n".join(out))

            # --status prints step table and exits 0.
            status_out: list[str] = []
            rc_status = setup_cli.main(
                [SERIAL, "--adb", "adb", "--model", "SM-G970F", "--status"],
                home=Path(tmp),
                run=world.run,
                say=status_out.append,
                log=lambda _l: None,
            )
            self.assertEqual(rc_status, 0)
            self.assertIn("k2-enroll", "\n".join(status_out))

            # Missing kit images fails preflight and releases the device lock.
            world2 = FakePhoneWorld()
            out2: list[str] = []
            lock_dir = Path(tmp) / "locks"
            kit_dir = Path(tmp) / "kit"
            kit_dir.mkdir()
            rc2 = setup_cli.main(
                [
                    SERIAL,
                    "--adb",
                    "adb",
                    "--name",
                    "court-s10e-4",
                    "--kit",
                    str(kit_dir),
                    "--lock-dir",
                    str(lock_dir),
                    "--skip-k2",
                ],
                home=Path(tmp),
                run=world2.run,
                say=out2.append,
                log=lambda _l: None,
            )
            self.assertEqual(rc2, 1)
            self.assertIn("kit image missing", "\n".join(out2))
            self.assertFalse((lock_dir / SERIAL).exists())


if __name__ == "__main__":
    unittest.main()
