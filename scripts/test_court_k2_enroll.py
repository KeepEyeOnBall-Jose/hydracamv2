#!/usr/bin/env python3
"""Unit tests for K2 Court Cloud single-device-record enrollment (C1 1.29).

All HTTP and ADB calls are mocked or run against an in-process loopback HTTP
server; no physical USB phone or external network access is required.
"""

from __future__ import annotations

import http.server
import io
import json
import os
import stat
import sys
import tempfile
import threading
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import court_k2_enroll as cli  # noqa: E402
from hydracam_lib import court_k2 as k2  # noqa: E402
from hydracam_lib.proc import CommandResult  # noqa: E402


class FakeK2Server:
    """In-memory fake of K2 Court Cloud (C0/C1 1.29 single device record)."""

    def __init__(self) -> None:
        self.admin_token = "admin-test-token"
        self.contract_version = "1.29"
        self.courts: dict[str, dict[str, object]] = {
            "airport-squash-2": {
                "id": "0192f3a0-7c1e-7a00-8000-000000000020",
                "slug": "airport-squash-2",
                "name": "Court 2",
                "club": "Airport Squash Berlin",
                "cameras": [
                    {"slot": "left", "label": "Left", "online": False},
                    {"slot": "center", "label": "Center", "online": False},
                    {"slot": "right", "label": "Right", "online": False},
                ],
            },
            "airport-squash-3": {
                "id": "0192f3a0-7c1e-7a00-8000-000000000030",
                "slug": "airport-squash-3",
                "name": "Court 3",
                "club": "Airport Squash Berlin",
                "cameras": [
                    {"slot": "left", "label": "Left", "online": False},
                    {"slot": "center", "label": "Center", "online": False},
                    {"slot": "right", "label": "Right", "online": False},
                ],
            },
        }
        self.devices: dict[str, dict[str, object]] = {}
        self.secrets: dict[str, str] = {}
        self.aliases: dict[tuple[str, str], dict[str, object]] = {}
        self.requests: list[tuple[str, str, object]] = []
        self._seq = 0

    def transport(
        self,
        method: str,
        url: str,
        *,
        headers: dict[str, str],
        body: bytes | None,
        timeout: float,
    ) -> tuple[int, bytes]:
        del timeout
        parsed = json.loads(body.decode("utf-8")) if body else None
        path = "/" + url.split("://", 1)[1].split("/", 1)[1]
        self.requests.append((method, path, parsed))

        if method == "GET" and path == "/health":
            return 200, json.dumps(
                {
                    "status": "ok",
                    "service": "court-cloud",
                    "contractVersion": self.contract_version,
                    "db": "ok",
                    "devicesOnline": sum(
                        1 for d in self.devices.values() if d.get("online")
                    ),
                }
            ).encode("utf-8")

        if method == "GET" and path.startswith("/api/courts/"):
            slug = path.removeprefix("/api/courts/")
            court = self.courts.get(slug)
            if court is None:
                return 404, json.dumps({"error": "court-not-found"}).encode("utf-8")
            return 200, json.dumps(court).encode("utf-8")

        if method == "POST" and path == "/device/v1/token":
            device_id = parsed["deviceId"]
            secret = parsed["secret"]
            dev = self.devices.get(device_id)
            if not dev or dev.get("revoked") or self.secrets.get(device_id) != secret:
                return 401, json.dumps({"error": "invalid-device"}).encode("utf-8")
            return 200, json.dumps(
                {"accessToken": f"jwt-for-{device_id}", "expiresAt": 1900000000000}
            ).encode("utf-8")

        if path.startswith("/internal/v1/"):
            auth = headers.get("Authorization") or headers.get("authorization") or ""
            if auth != f"Bearer {self.admin_token}":
                return 401, json.dumps({"error": "unauthorized"}).encode("utf-8")

        if method == "GET" and path == "/internal/v1/devices":
            return 200, json.dumps(
                {"devices": list(self.devices.values())}
            ).encode("utf-8")

        if method == "POST" and path == "/internal/v1/devices":
            court = self.courts.get(parsed["courtSlug"])
            if court is None:
                return 404, json.dumps({"error": "court-not-found"}).encode("utf-8")
            slot = parsed["slot"]
            valid_slots = {c["slot"] for c in court["cameras"]}  # type: ignore[index]
            if slot not in valid_slots:
                return 400, json.dumps({"error": "unknown-slot"}).encode("utf-8")

            device_id = parsed.get("deviceId")
            for other_id, other in self.devices.items():
                if (
                    other_id != device_id
                    and not other["revoked"]
                    and other["courtId"] == court["id"]
                    and other["slot"] == slot
                ):
                    return 409, json.dumps({"error": "slot-taken"}).encode("utf-8")

            self._seq += 1
            if not device_id:
                device_id = f"0192f3a0-0000-7000-8000-{self._seq:012d}"
            secret = f"secret-{self._seq}-{device_id[-4:]}"
            prev = self.devices.get(device_id)
            mount_rev = int(prev["mountRev"]) + 1 if prev else 1
            self.devices[device_id] = {
                "id": device_id,
                "courtId": court["id"],
                "slot": slot,
                "name": parsed.get("name", ""),
                "mountRev": mount_rev,
                "appVersion": None,
                "contractVersion": self.contract_version,
                "model": None,
                "androidSdk": None,
                "rooted": None,
                "caps": None,
                "lastState": None,
                "online": False,
                "lastSeenAtMs": None,
                "revoked": False,
                "connected": False,
            }
            self.secrets[device_id] = secret
            return 201, json.dumps(
                {"deviceId": device_id, "secret": secret, "mountRev": mount_rev}
            ).encode("utf-8")

        if (
            method == "POST"
            and path.startswith("/internal/v1/devices/")
            and path.endswith("/assign")
        ):
            device_id = path.removeprefix("/internal/v1/devices/").removesuffix("/assign")
            dev = self.devices.get(device_id)
            if not dev or dev["revoked"]:
                return 404, json.dumps({"error": "device-not-found"}).encode("utf-8")
            court = self.courts.get(parsed["courtSlug"])
            if court is None:
                return 404, json.dumps({"error": "court-not-found"}).encode("utf-8")
            slot = parsed["slot"]
            valid_slots = {c["slot"] for c in court["cameras"]}  # type: ignore[index]
            if slot not in valid_slots:
                return 400, json.dumps({"error": "unknown-slot"}).encode("utf-8")
            for other_id, other in self.devices.items():
                if (
                    other_id != device_id
                    and not other["revoked"]
                    and other["courtId"] == court["id"]
                    and other["slot"] == slot
                ):
                    return 409, json.dumps({"error": "slot-taken"}).encode("utf-8")
            dev["courtId"] = court["id"]
            dev["slot"] = slot
            dev["mountRev"] = int(dev["mountRev"]) + 1
            return 200, json.dumps(dev).encode("utf-8")

        if method == "GET" and path.startswith("/internal/v1/aliases/"):
            rest = path.removeprefix("/internal/v1/aliases/")
            source, legacy_id = rest.split("/", 1)
            alias = self.aliases.get((source, legacy_id))
            if alias is None:
                return 404, json.dumps({"error": "alias-not-found"}).encode("utf-8")
            dev = self.devices.get(str(alias["deviceId"]))
            court_slug = None
            for slug, c in self.courts.items():
                if dev and c["id"] == dev.get("courtId"):
                    court_slug = slug
            return 200, json.dumps(
                {
                    **alias,
                    "kind": "device",
                    "courtId": dev.get("courtId") if dev else None,
                    "courtSlug": court_slug,
                    "slot": dev.get("slot") if dev else None,
                }
            ).encode("utf-8")

        if method == "POST" and path == "/internal/v1/aliases":
            counts = {"created": 0, "updated": 0, "unchanged": 0}
            for entry in parsed["aliases"]:
                key = (entry["source"], entry["legacyId"])
                if entry["deviceId"] not in self.devices:
                    return 404, json.dumps({"error": "device-not-found"}).encode("utf-8")
                prev = self.aliases.get(key)
                if (
                    prev
                    and prev["deviceId"] == entry["deviceId"]
                    and prev["note"] == entry.get("note", "")
                ):
                    counts["unchanged"] += 1
                else:
                    self.aliases[key] = {
                        "source": entry["source"],
                        "legacyId": entry["legacyId"],
                        "deviceId": entry["deviceId"],
                        "note": entry.get("note", ""),
                    }
                    counts["updated" if prev else "created"] += 1
            return 200, json.dumps(counts).encode("utf-8")

        return 404, json.dumps({"error": "not-found"}).encode("utf-8")


class FakeAdbWorld:
    """Fake adb CLI runner recording argv and stdin without touching any phone."""

    def __init__(self, devices_output: str, serial_by_ep: dict[str, str]) -> None:
        self.devices_output = devices_output
        self.serial_by_ep = serial_by_ep
        self.calls: list[list[str]] = []
        self.inputs: list[str] = []
        self.magisk_policies: list[str] = []
        self.uid = "10234"
        self.root_ok = True
        self.app_installed = True
        self.enroll_ok = True

    def __call__(
        self,
        command: list[str],
        *,
        timeout: int,
        input_text: str | None = None,
    ) -> CommandResult:
        del timeout
        self.calls.append(list(command))
        if input_text is not None:
            self.inputs.append(input_text)
        if command[1:] == ["devices", "-l"]:
            return CommandResult(0, self.devices_output, "")
        ep = command[2]
        if command[3] != "shell":
            return CommandResult(0, "", "")
        cmd = command[4]
        if cmd == "getprop ro.serialno":
            return CommandResult(0, self.serial_by_ep.get(ep, "") + "\n", "")
        if cmd == "getprop ro.boot.serialno":
            return CommandResult(0, self.serial_by_ep.get(ep, "") + "\n", "")
        if cmd == 'su -c "id -u"' or cmd == "su -c id":
            return CommandResult(0, "0\n" if self.root_ok else "2000\n", "")
        if cmd.startswith("dumpsys package "):
            if not self.app_installed:
                return CommandResult(0, "", "")
            return CommandResult(0, f"    userId={self.uid}\n", "")
        if "magisk --sqlite 'INSERT" in cmd:
            self.magisk_policies.append(cmd)
            return CommandResult(0, "", "")
        if "magisk --sqlite 'SELECT" in cmd:
            return CommandResult(0, "policy=2\n", "")
        if cmd == "su" and input_text is not None:
            if "CourtEnrollReceiver" in input_text:
                if self.enroll_ok:
                    return CommandResult(0, 'Broadcast completed: result=-1, data="ok"\n', "")
                return CommandResult(0, 'Broadcast completed: result=0, data="slot is required"\n', "")
            return CommandResult(0, "", "")
        return CommandResult(0, "", "")


class ContractAndEnrollmentValidationTests(unittest.TestCase):
    def test_contract_version_1_29_helpers(self) -> None:
        self.assertEqual(k2.C1_CONTRACT_VERSION, "1.29")
        self.assertTrue(k2.contract_at_least("1.29", "1.29"))
        self.assertTrue(k2.contract_at_least("1.29.0", "1.29"))
        self.assertTrue(k2.contract_at_least("1.30", "1.29"))
        self.assertFalse(k2.contract_at_least("1.28", "1.29"))
        self.assertFalse(k2.contract_at_least("1.10.1", "1.11"))
        self.assertFalse(k2.contract_at_least(None, "1.29"))
        self.assertFalse(k2.contract_at_least("invalid", "1.29"))

        self.assertEqual(k2.contract_skew("1.29"), "same")
        self.assertEqual(k2.contract_skew("1.29.0"), "same")
        self.assertEqual(k2.contract_skew("1.28"), "older")
        self.assertEqual(k2.contract_skew("1.30"), "newer")
        self.assertEqual(k2.contract_skew(None), "unknown")

    def test_url_and_enrollment_validation_and_secret_redaction(self) -> None:
        self.assertTrue(k2.is_allowed_k2_url("https://app.kvisor.com"))
        self.assertTrue(k2.is_allowed_k2_url("http://127.0.0.1:3050"))
        self.assertTrue(k2.is_allowed_k2_url("http://localhost:8787"))
        self.assertFalse(k2.is_allowed_k2_url("http://app.kvisor.com"))
        self.assertFalse(k2.is_allowed_k2_url("ftp://app.kvisor.com"))

        with self.assertRaisesRegex(ValueError, "app.kvisor.com"):
            k2.validate_k2_url("https://kvisor.com")

        enrollment = k2.CourtEnrollment(
            k2_url="https://app.kvisor.com/",
            device_id="dev-123",
            secret="super'secret $val",
            court_id="court-uuid-1",
            slot="left",
            mount_rev=2,
        )
        enrollment.raise_for_invalid()
        self.assertNotIn("super'secret", repr(enrollment))
        self.assertNotIn("super'secret", str(enrollment))
        self.assertNotIn("super'secret", json.dumps(enrollment.to_dict()))
        self.assertEqual(
            enrollment.to_dict(include_secret=True)["secret"],
            "super'secret $val",
        )
        broadcast = enrollment.build_enroll_broadcast_command()
        self.assertIn("--es k2Url https://app.kvisor.com", broadcast)
        self.assertIn("--ei mountRev 2", broadcast)
        self.assertIn("super'\"'\"'secret $val", broadcast)

        bad_rev = k2.CourtEnrollment(
            k2_url="https://app.kvisor.com",
            device_id="dev-123",
            secret="sec",
            court_id="court-uuid-1",
            slot="left",
            mount_rev=-1,
        )
        with self.assertRaisesRegex(ValueError, "mountRev"):
            bad_rev.raise_for_invalid()

        bad_court = k2.CourtEnrollment(
            k2_url="https://app.kvisor.com",
            device_id="dev-123",
            secret="sec",
            court_id="../escape",
            slot="left",
            mount_rev=1,
        )
        with self.assertRaisesRegex(ValueError, "courtId"):
            bad_court.raise_for_invalid()

    def test_default_http_transport_never_follows_redirects_on_token_post(self) -> None:
        redirect_hits: list[str] = []

        class RedirectHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                if self.path == "/device/v1/token":
                    self.send_response(307)
                    self.send_header("Location", "/steal")
                    self.end_headers()
                    return
                redirect_hits.append(self.path)
                self.send_response(200)
                self.end_headers()

            def log_message(self, format, *args):  # noqa: A002, ANN002, ANN003
                del format, args

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RedirectHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}"
            client = k2.K2CourtCloudClient(url)
            with self.assertRaises(k2.K2Error) as ctx:
                client.verify_device_token("dev-1", "secret-1")
            self.assertEqual(ctx.exception.status, 307)
            self.assertEqual(redirect_hits, [])
        finally:
            server.shutdown()
            server.server_close()


class K2SingleDeviceRecordEnrollmentTests(unittest.TestCase):
    def test_health_detects_contract_1_29_and_skew(self) -> None:
        server = FakeK2Server()
        client = k2.K2CourtCloudClient(
            "https://app.kvisor.com",
            admin_token=server.admin_token,
            transport=server.transport,
        )
        self.assertEqual(client.health()["contractSkew"], "same")
        server.contract_version = "1.28"
        self.assertEqual(client.health()["contractSkew"], "older")
        server.contract_version = "1.30"
        self.assertEqual(client.health()["contractSkew"], "newer")

    def test_first_enrollment_creates_single_record_and_registers_aliases(self) -> None:
        server = FakeK2Server()
        client = k2.K2CourtCloudClient(
            "https://app.kvisor.com",
            admin_token=server.admin_token,
            transport=server.transport,
        )

        outcome = k2.enroll_single_k2_device(
            client=client,
            court_slug="airport-squash-2",
            slot="left",
            serial="RF8M40MT6AW",
            host="court-s10e-3",
            name="Court S10e #3",
        )

        self.assertEqual(outcome.action, "created")
        self.assertEqual(
            outcome.enrollment.court_id,
            server.courts["airport-squash-2"]["id"],
        )
        self.assertEqual(outcome.enrollment.slot, "left")
        self.assertEqual(outcome.enrollment.mount_rev, 1)
        self.assertEqual(len(server.devices), 1)
        self.assertEqual(
            server.aliases[("adb-serial", "RF8M40MT6AW")]["deviceId"],
            outcome.enrollment.device_id,
        )
        self.assertEqual(
            server.aliases[("fleet-host", "court-s10e-3")]["deviceId"],
            outcome.enrollment.device_id,
        )

    def test_re_enroll_is_idempotent_with_cached_valid_secret(self) -> None:
        server = FakeK2Server()
        client = k2.K2CourtCloudClient(
            "https://app.kvisor.com",
            admin_token=server.admin_token,
            transport=server.transport,
        )

        first = k2.enroll_single_k2_device(
            client=client,
            court_slug="airport-squash-2",
            slot="left",
            serial="RF8M40MT6AW",
            host="court-s10e-3",
        )
        second = k2.enroll_single_k2_device(
            client=client,
            court_slug="airport-squash-2",
            slot="left",
            serial="RF8M40MT6AW",
            host="court-s10e-3",
            cached_secret=first.enrollment.secret,
        )

        self.assertEqual(second.action, "reused")
        self.assertEqual(second.enrollment.device_id, first.enrollment.device_id)
        self.assertEqual(second.enrollment.secret, first.enrollment.secret)
        self.assertEqual(second.enrollment.mount_rev, 1)
        self.assertEqual(len(server.devices), 1)

    def test_moving_slot_reassigns_single_record_and_bumps_mount_rev(self) -> None:
        server = FakeK2Server()
        client = k2.K2CourtCloudClient(
            "https://app.kvisor.com",
            admin_token=server.admin_token,
            transport=server.transport,
        )

        first = k2.enroll_single_k2_device(
            client=client,
            court_slug="airport-squash-2",
            slot="left",
            serial="RF8M40MT6AW",
            host="court-s10e-3",
        )
        moved = k2.enroll_single_k2_device(
            client=client,
            court_slug="airport-squash-3",
            slot="right",
            serial="RF8M40MT6AW",
            host="court-s10e-3",
            cached_secret=first.enrollment.secret,
        )

        self.assertEqual(moved.action, "reassigned")
        self.assertEqual(moved.enrollment.device_id, first.enrollment.device_id)
        self.assertEqual(moved.enrollment.secret, first.enrollment.secret)
        self.assertEqual(
            moved.enrollment.court_id,
            server.courts["airport-squash-3"]["id"],
        )
        self.assertEqual(moved.enrollment.slot, "right")
        self.assertEqual(moved.enrollment.mount_rev, 2)
        self.assertEqual(len(server.devices), 1)

    def test_rotate_secret_reuses_same_device_id_via_alias(self) -> None:
        server = FakeK2Server()
        client = k2.K2CourtCloudClient(
            "https://app.kvisor.com",
            admin_token=server.admin_token,
            transport=server.transport,
        )

        first = k2.enroll_single_k2_device(
            client=client,
            court_slug="airport-squash-2",
            slot="left",
            serial="RF8M40MT6AW",
            host="court-s10e-3",
        )
        rotated = k2.enroll_single_k2_device(
            client=client,
            court_slug="airport-squash-2",
            slot="left",
            serial="RF8M40MT6AW",
            host="court-s10e-3",
            cached_secret=first.enrollment.secret,
            rotate_secret=True,
        )

        self.assertEqual(rotated.action, "re-enrolled")
        self.assertEqual(rotated.enrollment.device_id, first.enrollment.device_id)
        self.assertNotEqual(rotated.enrollment.secret, first.enrollment.secret)
        self.assertEqual(rotated.enrollment.mount_rev, 2)
        self.assertEqual(len(server.devices), 1)

    def test_failures_slot_taken_bad_court_bad_slot_and_identity_conflict(self) -> None:
        server = FakeK2Server()
        client = k2.K2CourtCloudClient(
            "https://app.kvisor.com",
            admin_token=server.admin_token,
            transport=server.transport,
        )

        with self.assertRaisesRegex(k2.K2Error, "court-not-found"):
            k2.enroll_single_k2_device(
                client=client,
                court_slug="missing-court",
                slot="left",
                serial="S1",
            )

        with self.assertRaisesRegex(k2.K2Error, "unknown-slot"):
            k2.enroll_single_k2_device(
                client=client,
                court_slug="airport-squash-2",
                slot="ceiling",
                serial="S1",
            )

        first = k2.enroll_single_k2_device(
            client=client,
            court_slug="airport-squash-2",
            slot="left",
            serial="S1",
        )
        with self.assertRaisesRegex(k2.K2Error, "slot-taken"):
            k2.enroll_single_k2_device(
                client=client,
                court_slug="airport-squash-2",
                slot="left",
                serial="S2",
            )

        with self.assertRaisesRegex(k2.DeviceIdentityConflictError, "alias"):
            k2.enroll_single_k2_device(
                client=client,
                court_slug="airport-squash-2",
                slot="left",
                serial="S1",
                cached_device_id="other-device-id",
            )
        self.assertIn(first.enrollment.device_id, server.devices)


class AdbResolutionAndCliTests(unittest.TestCase):
    def test_adb_endpoint_resolution_auto_select_and_failures(self) -> None:
        devices_out = (
            "List of devices attached\n"
            "RF8M40MT6AW device usb:1-1 model:SM_G970F\n"
            "127.0.0.1:15561 device product:beyond0\n"
            "court-s10e-3:5555 device product:beyond0\n"
        )
        world = FakeAdbWorld(
            devices_out,
            {
                "RF8M40MT6AW": "RF8M40MT6AW",
                "127.0.0.1:15561": "RF8M40MT6AW",
                "court-s10e-3:5555": "RF8M40MT6AW",
            },
        )
        ep = k2.resolve_adb_endpoint(
            "adb",
            serial="RF8M40MT6AW",
            host="court-s10e-3",
            port=15561,
            runner=world,
        )
        self.assertEqual(ep, "RF8M40MT6AW")

        # Auto-selects single authorized USB device; fails when ambiguous or absent.
        single_world = FakeAdbWorld(
            "List of devices attached\nRF8M40MT6AW device usb:1-1\n",
            {"RF8M40MT6AW": "RF8M40MT6AW"},
        )
        self.assertEqual(k2.resolve_adb_endpoint("adb", runner=single_world), "RF8M40MT6AW")
        with self.assertRaisesRegex(RuntimeError, "Multiple authorized"):
            k2.resolve_adb_endpoint("adb", runner=world)
        with self.assertRaisesRegex(RuntimeError, "No authorized"):
            k2.resolve_adb_endpoint("adb", runner=FakeAdbWorld("List of devices attached\n", {}))

        # Falls back to verified tunnel when USB is absent.
        tunnel_world = FakeAdbWorld(
            "List of devices attached\n127.0.0.1:15561 device\n",
            {"127.0.0.1:15561": "RF8M40MT6AW"},
        )
        self.assertEqual(
            k2.resolve_adb_endpoint(
                "adb",
                serial="RF8M40MT6AW",
                host="court-s10e-3",
                port=15561,
                runner=tunnel_world,
            ),
            "127.0.0.1:15561",
        )

        # Rejects a tunnel whose ro.serialno belongs to another phone.
        wrong_phone_world = FakeAdbWorld(
            "List of devices attached\n127.0.0.1:15561 device\n",
            {"127.0.0.1:15561": "OTHER_SERIAL"},
        )
        with self.assertRaisesRegex(RuntimeError, "serial"):
            k2.resolve_adb_endpoint(
                "adb",
                serial="RF8M40MT6AW",
                port=15561,
                runner=wrong_phone_world,
            )

        # Clear unauthorized failure message.
        unauth_world = FakeAdbWorld(
            "List of devices attached\nRF8M40MT6AW unauthorized usb:1-1\n",
            {},
        )
        with self.assertRaisesRegex(RuntimeError, "unauthorized"):
            k2.resolve_adb_endpoint("adb", serial="RF8M40MT6AW", runner=unauth_world)

    def test_cli_enroll_pushes_via_stdin_without_leaking_secret_and_writes_0600_creds(
        self,
    ) -> None:
        server = FakeK2Server()
        world = FakeAdbWorld(
            "List of devices attached\nRF8M40MT6AW device model:SM_G970F\n",
            {"RF8M40MT6AW": "RF8M40MT6AW"},
        )
        with tempfile.TemporaryDirectory() as tmp:
            creds_file = Path(tmp) / "court-devices.json"
            lock_dir = Path(tmp) / "locks"
            stdout = io.StringIO()
            old_token = os.environ.get("COURT_CLOUD_ADMIN_TOKEN")
            os.environ["COURT_CLOUD_ADMIN_TOKEN"] = server.admin_token
            try:
                with redirect_stdout(stdout):
                    rc = cli.main(
                        [
                            "--adb",
                            "adb",
                            "--k2",
                            "https://app.kvisor.com",
                            "--court",
                            "airport-squash-2",
                            "--slot",
                            "left",
                            "--serial",
                            "RF8M40MT6AW",
                            "--name",
                            "court-s10e-3",
                            "--creds-out",
                            str(creds_file),
                            "--lock-dir",
                            str(lock_dir),
                        ],
                        runner=world,
                        transport=server.transport,
                    )
            finally:
                if old_token is None:
                    os.environ.pop("COURT_CLOUD_ADMIN_TOKEN", None)
                else:
                    os.environ["COURT_CLOUD_ADMIN_TOKEN"] = old_token

            self.assertEqual(rc, 0)
            output = stdout.getvalue()
            issued_secret = next(iter(server.secrets.values()))
            self.assertNotIn(issued_secret, output)
            self.assertNotIn(issued_secret, json.dumps(world.calls))
            self.assertTrue(
                any(
                    "CourtEnrollReceiver" in inp
                    and issued_secret in inp
                    and "--ei mountRev 1" in inp
                    for inp in world.inputs
                )
            )
            self.assertTrue(creds_file.exists())
            self.assertEqual(stat.S_IMODE(creds_file.stat().st_mode), 0o600)
            saved = json.loads(creds_file.read_text(encoding="utf-8"))
            self.assertEqual(len(saved), 1)
            self.assertEqual(saved[0]["mountRev"], 1)
            self.assertFalse((lock_dir / "RF8M40MT6AW").exists())

    def test_cli_failures_noroot_noapp_and_bad_admin_token_release_lock(self) -> None:
        server = FakeK2Server()
        with tempfile.TemporaryDirectory() as tmp:
            creds_file = Path(tmp) / "court-devices.json"
            lock_dir = Path(tmp) / "locks"
            old_token = os.environ.get("COURT_CLOUD_ADMIN_TOKEN")
            try:
                os.environ["COURT_CLOUD_ADMIN_TOKEN"] = "wrong-token"
                world_ok = FakeAdbWorld(
                    "List of devices attached\nRF8M40MT6AW device\n",
                    {"RF8M40MT6AW": "RF8M40MT6AW"},
                )
                with redirect_stderr(io.StringIO()):
                    rc_auth = cli.main(
                        [
                            "--adb",
                            "adb",
                            "--court",
                            "airport-squash-2",
                            "--slot",
                            "left",
                            "--serial",
                            "RF8M40MT6AW",
                            "--creds-out",
                            str(creds_file),
                            "--lock-dir",
                            str(lock_dir),
                        ],
                        runner=world_ok,
                        transport=server.transport,
                    )
                self.assertEqual(rc_auth, 1)
                self.assertFalse((lock_dir / "RF8M40MT6AW").exists())

                os.environ["COURT_CLOUD_ADMIN_TOKEN"] = server.admin_token
                world_no_root = FakeAdbWorld(
                    "List of devices attached\nRF8M40MT6AW device\n",
                    {"RF8M40MT6AW": "RF8M40MT6AW"},
                )
                world_no_root.root_ok = False
                with redirect_stderr(io.StringIO()):
                    rc_noroot = cli.main(
                        [
                            "--adb",
                            "adb",
                            "--court",
                            "airport-squash-2",
                            "--slot",
                            "left",
                            "--serial",
                            "RF8M40MT6AW",
                            "--creds-out",
                            str(creds_file),
                            "--lock-dir",
                            str(lock_dir),
                        ],
                        runner=world_no_root,
                        transport=server.transport,
                    )
                self.assertEqual(rc_noroot, 1)
                self.assertFalse((lock_dir / "RF8M40MT6AW").exists())

                world_no_app = FakeAdbWorld(
                    "List of devices attached\nRF8M40MT6AW device\n",
                    {"RF8M40MT6AW": "RF8M40MT6AW"},
                )
                world_no_app.app_installed = False
                with redirect_stderr(io.StringIO()):
                    rc_noapp = cli.main(
                        [
                            "--adb",
                            "adb",
                            "--court",
                            "airport-squash-2",
                            "--slot",
                            "left",
                            "--serial",
                            "RF8M40MT6AW",
                            "--creds-out",
                            str(creds_file),
                            "--lock-dir",
                            str(lock_dir),
                        ],
                        runner=world_no_app,
                        transport=server.transport,
                    )
                self.assertEqual(rc_noapp, 1)
                self.assertFalse((lock_dir / "RF8M40MT6AW").exists())
            finally:
                if old_token is None:
                    os.environ.pop("COURT_CLOUD_ADMIN_TOKEN", None)
                else:
                    os.environ["COURT_CLOUD_ADMIN_TOKEN"] = old_token

    def test_cli_creds_batch_mode_releases_lock_and_respects_mount_rev(self) -> None:
        server = FakeK2Server()
        world = FakeAdbWorld(
            "List of devices attached\nRF8M40MT6AW device\n",
            {"RF8M40MT6AW": "RF8M40MT6AW"},
        )
        with tempfile.TemporaryDirectory() as tmp:
            creds_file = Path(tmp) / "devices.json"
            creds_file.write_text(
                json.dumps(
                    [
                        {
                            "host": "court-s10e-3",
                            "serial": "RF8M40MT6AW",
                            "courtSlug": "airport-squash-2",
                            "courtId": server.courts["airport-squash-2"]["id"],
                            "slot": "left",
                            "deviceId": "dev-existing",
                            "secret": "batch-secret-xyz",
                            "mountRev": 4,
                        }
                    ]
                ),
                encoding="utf-8",
            )
            os.chmod(creds_file, 0o600)
            lock_dir = Path(tmp) / "locks"
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                rc = cli.main(
                    [
                        "--adb",
                        "adb",
                        "--creds",
                        str(creds_file),
                        "--lock-dir",
                        str(lock_dir),
                        "all",
                    ],
                    runner=world,
                )

            self.assertEqual(rc, 0)
            self.assertNotIn("batch-secret-xyz", stdout.getvalue())
            self.assertTrue(
                any(
                    "--ei mountRev 4" in inp and "dev-existing" in inp
                    for inp in world.inputs
                )
            )
            self.assertFalse((lock_dir / "RF8M40MT6AW").exists())

    def test_cli_clear_mode_clears_enrollment_and_reports_failure(self) -> None:
        world = FakeAdbWorld(
            "List of devices attached\nRF8M40MT6AW device\n",
            {"RF8M40MT6AW": "RF8M40MT6AW"},
        )
        with tempfile.TemporaryDirectory() as tmp:
            lock_dir = Path(tmp) / "locks"
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                rc = cli.main(
                    [
                        "--adb",
                        "adb",
                        "--clear",
                        "--serial",
                        "RF8M40MT6AW",
                        "--lock-dir",
                        str(lock_dir),
                    ],
                    runner=world,
                )
            self.assertEqual(rc, 0)
            self.assertTrue(
                any("com.amaia23.hydracam.court.CLEAR" in inp for inp in world.inputs)
            )

            world.enroll_ok = False
            with redirect_stderr(io.StringIO()):
                rc_fail = cli.main(
                    [
                        "--adb",
                        "adb",
                        "--clear",
                        "--serial",
                        "RF8M40MT6AW",
                        "--lock-dir",
                        str(lock_dir),
                    ],
                    runner=world,
                )
            self.assertEqual(rc_fail, 1)
            self.assertFalse((lock_dir / "RF8M40MT6AW").exists())


if __name__ == "__main__":
    unittest.main()
