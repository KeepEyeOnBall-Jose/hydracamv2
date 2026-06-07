#!/usr/bin/env python3
"""Tests for the rotating master/slave HydraCam matrix runner."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
import time
from pathlib import Path

SCRIPT_PATH = Path(__file__).with_name("run_rotating_master_slave_matrix.py")


def load_module():
    spec = importlib.util.spec_from_file_location(
        "run_rotating_master_slave_matrix",
        SCRIPT_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load run_rotating_master_slave_matrix.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def matrix_target(
    module,
    device_id: str,
    platform: str,
    *,
    capture_enabled: bool = True,
    known_blocker: str | None = None,
):
    return module.MatrixTarget(
        device_id=device_id,
        label=device_id,
        platform=platform,
        runtime=platform,
        lens="autoBack",
        profile="standard1080p30",
        host="127.0.0.1",
        bridge_port=6400,
        capture_enabled=capture_enabled,
        expected_result="capture" if capture_enabled else "launch_only",
        known_blocker=known_blocker,
    )


class RotatingMasterSlaveMatrixTests(unittest.TestCase):
    def test_build_rotations_makes_each_capture_device_master_once(self) -> None:
        module = load_module()
        targets = [
            matrix_target(module, "android-a", "android"),
            matrix_target(module, "iphone", "ios_physical"),
            matrix_target(module, "macos", "macos"),
            matrix_target(
                module,
                "simulator",
                "ios_simulator",
                capture_enabled=False,
            ),
        ]

        rotations = module.build_rotations(targets)

        self.assertEqual([rotation.master.device_id for rotation in rotations], [
            "android-a",
            "iphone",
            "macos",
        ])
        self.assertEqual(
            [client.device_id for client in rotations[0].clients],
            ["iphone", "macos", "simulator"],
        )

    def test_filter_targets_keeps_only_requested_device_ids(self) -> None:
        module = load_module()
        targets = [
            matrix_target(module, "android-a", "android"),
            matrix_target(module, "iphone", "ios_physical"),
            matrix_target(module, "macos", "macos"),
        ]

        filtered = module.filter_targets_by_device_ids(
            targets,
            ["macos", "android-a"],
        )

        self.assertEqual(
            [target.device_id for target in filtered],
            ["android-a", "macos"],
        )

    def test_filter_targets_rejects_unknown_device_id(self) -> None:
        module = load_module()
        targets = [matrix_target(module, "android-a", "android")]

        with self.assertRaisesRegex(module.MatrixConfigError, "unknown"):
            module.filter_targets_by_device_ids(targets, ["unknown"])

    def test_filter_rotations_keeps_only_requested_masters(self) -> None:
        module = load_module()
        targets = [
            matrix_target(module, "android-a", "android"),
            matrix_target(module, "iphone", "ios_physical"),
            matrix_target(module, "macos", "macos"),
        ]
        rotations = module.build_rotations(targets)

        filtered = module.filter_rotations_by_master_ids(rotations, ["iphone"])

        self.assertEqual(
            [rotation.master.device_id for rotation in filtered],
            ["iphone"],
        )

    def test_filter_rotations_rejects_unknown_master_id(self) -> None:
        module = load_module()
        rotations = [
            module.MatrixRotation(
                master=matrix_target(module, "android-a", "android"),
                clients=[],
            )
        ]

        with self.assertRaisesRegex(module.MatrixConfigError, "unknown"):
            module.filter_rotations_by_master_ids(rotations, ["iphone"])

    def test_android_apk_is_required_only_when_android_targets_are_included(self) -> None:
        module = load_module()

        self.assertFalse(
            module.requires_android_apk([
                matrix_target(module, "macos", "macos"),
                matrix_target(module, "simulator", "ios_simulator", capture_enabled=False),
            ])
        )
        self.assertTrue(
            module.requires_android_apk([
                matrix_target(module, "android-a", "android"),
                matrix_target(module, "macos", "macos"),
            ])
        )

    def test_android_start_command_for_slave_forces_master_ip(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")

        command = module.build_android_start_command(
            target,
            role="slave",
            master_ip="192.168.178.141",
        )

        self.assertIn("--es", command)
        self.assertIn("role", command)
        self.assertIn("slave", command)
        self.assertIn("preferredMasterIp", command)
        self.assertIn("192.168.178.141", command)
        self.assertIn("--ez", command)
        self.assertIn("forceSlaveMode", command)
        self.assertIn("true", command)

    def test_parse_android_wifi_ip_prefers_wlan0_address(self) -> None:
        module = load_module()

        ip_address = module.parse_android_wifi_ip(
            "12: wlan0: <BROADCAST>\n"
            "    inet 192.168.178.63/24 brd 192.168.178.255 scope global wlan0\n",
            "",
        )

        self.assertEqual(ip_address, "192.168.178.63")

    def test_parse_android_wifi_ip_falls_back_to_route_source(self) -> None:
        module = load_module()

        ip_address = module.parse_android_wifi_ip(
            "",
            "1.1.1.1 via 192.168.178.1 dev wlan0 src 192.168.178.64 uid 2000\n",
        )

        self.assertEqual(ip_address, "192.168.178.64")

    def test_build_dry_run_summary_records_rotations_and_known_blockers(self) -> None:
        module = load_module()
        targets = [
            matrix_target(module, "android-a", "android"),
            matrix_target(
                module,
                module.S7_SERIAL,
                "android",
                known_blocker="s7_exynos_camera_timeout",
            ),
            matrix_target(module, "iphone", "ios_physical"),
            matrix_target(
                module,
                "simulator",
                "ios_simulator",
                capture_enabled=False,
            ),
        ]
        rotations = module.build_rotations(targets)

        summary = module.build_dry_run_summary(targets, rotations)

        self.assertEqual(summary["rotationCount"], 3)
        self.assertTrue(summary["sharedBarrierPerRotation"])
        self.assertEqual(
            summary["rotations"][1]["knownBlocker"],
            "s7_exynos_camera_timeout",
        )

    def test_flutter_target_launch_detaches_after_bridge_is_healthy(self) -> None:
        module = load_module()
        target = matrix_target(module, "iphone", "ios_physical")
        target = module.dataclasses.replace(
            target,
            host="192.168.178.141",
            bridge_port=4762,
        )
        events: list[tuple[str, str]] = []

        class FakeProcess:
            pass

        def fake_launch_flutter(device_id, _log_path, *, port, role, master_ip):
            events.append(("launch", f"{device_id}:{port}:{role}:{master_ip}"))
            return FakeProcess()

        def fake_wait_for_flutter_bridge(target, _process, _deadline):
            events.append(("wait", target.bridge_url))

        def fake_detach_flutter(process):
            self.assertIsInstance(process, FakeProcess)
            events.append(("detach", "process"))

        module.launch_flutter = fake_launch_flutter
        module.wait_for_flutter_bridge = fake_wait_for_flutter_bridge
        module.detach_flutter = fake_detach_flutter
        module.terminate_flutter_console_process = lambda _target: None

        with self.subTest("detaches"):
            process = module.launch_flutter_target(
                target,
                Path("/tmp/hydracam-rotation"),
                role="slave",
                master_ip="192.168.178.153",
                timeout=30,
            )

        self.assertIsNone(process)
        self.assertEqual(
            events,
            [
                ("launch", "iphone:4762:slave:192.168.178.153"),
                ("wait", "http://192.168.178.141:4762"),
                ("detach", "process"),
            ],
        )

    def test_build_flutter_app_terminate_commands_by_platform(self) -> None:
        module = load_module()

        ios = matrix_target(module, "iphone", "ios_physical")
        simulator = matrix_target(module, "simulator", "ios_simulator")
        macos = matrix_target(module, "macos", "macos")

        self.assertIsNone(module.build_flutter_app_terminate_command(ios))
        self.assertEqual(
            module.build_ios_process_list_command(ios, Path("/tmp/processes.json")),
            [
                "xcrun",
                "devicectl",
                "device",
                "info",
                "processes",
                "--device",
                "iphone",
                "--filter",
                "executable.path CONTAINS 'HydraCam'",
                "--json-output",
                "/tmp/processes.json",
                "--quiet",
            ],
        )
        self.assertEqual(
            module.build_flutter_app_terminate_command(simulator),
            ["xcrun", "simctl", "terminate", "simulator", module.IOS_BUNDLE_ID],
        )
        self.assertEqual(
            module.build_flutter_app_terminate_command(macos),
            ["pkill", "-x", "HydraCam"],
        )

    def test_build_ios_fast_launch_command_passes_runtime_role_environment(self) -> None:
        module = load_module()
        target = matrix_target(module, "iphone", "ios_physical")

        command = module.build_ios_fast_launch_command(
            target,
            role="slave",
            master_ip="192.168.178.153",
        )

        self.assertEqual(command[:5], [
            "xcrun",
            "devicectl",
            "device",
            "process",
            "launch",
        ])
        self.assertIn("--terminate-existing", command)
        self.assertIn("--environment-variables", command)
        environment_json = command[command.index("--environment-variables") + 1]
        self.assertEqual(
            module.json.loads(environment_json),
            {
                "HYDRACAM_AUTOMATION_FORCE_SLAVE": "true",
                "HYDRACAM_AUTOMATION_MASTER_IP": "192.168.178.153",
                "HYDRACAM_AUTOMATION_ROLE": "slave",
            },
        )
        self.assertEqual(command[-1], module.IOS_BUNDLE_ID)

    def test_fast_launch_can_start_ios_in_standby(self) -> None:
        module = load_module()
        target = matrix_target(module, "iphone", "ios_physical")

        command = module.build_ios_fast_launch_command(
            target,
            role="standby",
            master_ip=None,
        )

        environment_json = command[command.index("--environment-variables") + 1]
        self.assertEqual(
            module.json.loads(environment_json),
            {"HYDRACAM_AUTOMATION_ROLE": "standby"},
        )

    def test_runtime_role_payloads_rotate_one_master_and_parallel_slaves(self) -> None:
        module = load_module()
        master = matrix_target(module, "android-a", "android")
        iphone = matrix_target(module, "iphone", "ios_physical")
        macos = matrix_target(module, "macos", "macos")
        rotation = module.MatrixRotation(master=master, clients=[iphone, macos])

        payloads = module.build_runtime_role_payloads(
            rotation,
            master_host="192.168.178.153",
        )

        self.assertEqual(payloads["android-a"], {"role": "master"})
        self.assertEqual(
            payloads["iphone"],
            {
                "role": "slave",
                "preferredMasterIp": "192.168.178.153",
                "forceSlaveMode": True,
            },
        )
        self.assertEqual(payloads["macos"]["role"], "slave")

    def test_apply_runtime_role_switch_posts_set_role_to_every_target(self) -> None:
        module = load_module()
        master = matrix_target(module, "android-a", "android")
        iphone = matrix_target(module, "iphone", "ios_physical")
        macos = matrix_target(module, "macos", "macos")
        rotation = module.MatrixRotation(master=master, clients=[iphone, macos])
        calls: list[tuple[str, str, dict]] = []

        def fake_post_command(bridge_url, command, payload, _deadline):
            calls.append((bridge_url, command, dict(payload)))
            return {"result": payload}

        module.post_command = fake_post_command

        responses = module.apply_runtime_role_switch(
            rotation,
            targets=[master, iphone, macos],
            master_host="192.168.178.153",
            timeout=10,
        )

        self.assertEqual(set(responses), {"android-a", "iphone", "macos"})
        self.assertEqual([call[1] for call in calls], [
            "set_role",
            "set_role",
            "set_role",
        ])
        self.assertIn(
            ("http://127.0.0.1:6400", "set_role", {"role": "master"}),
            calls,
        )

    def test_apply_runtime_role_switch_posts_in_parallel(self) -> None:
        module = load_module()
        master = matrix_target(module, "android-a", "android")
        iphone = matrix_target(module, "iphone", "ios_physical")
        macos = matrix_target(module, "macos", "macos")
        rotation = module.MatrixRotation(master=master, clients=[iphone, macos])

        def fake_post_command(_bridge_url, _command, payload, _deadline):
            time.sleep(0.15)
            return {"result": payload}

        module.post_command = fake_post_command

        start = time.perf_counter()
        module.apply_runtime_role_switch(
            rotation,
            targets=[master, iphone, macos],
            master_host="192.168.178.153",
            timeout=10,
        )
        elapsed = time.perf_counter() - start

        self.assertLess(elapsed, 0.35)

    def test_build_runtime_role_switch_snapshot_records_elapsed_time(self) -> None:
        module = load_module()

        snapshot = module.build_runtime_role_switch_snapshot(
            {"macos": {"status": "ok"}},
            started_at="2026-06-07T17:34:19.000000",
            elapsed_seconds=0.1234,
        )

        self.assertEqual(snapshot["startedAt"], "2026-06-07T17:34:19.000000")
        self.assertEqual(snapshot["elapsedMs"], 123.4)
        self.assertEqual(snapshot["responses"]["macos"]["status"], "ok")

    def test_role_switch_only_flow_waits_for_clients_without_capture(self) -> None:
        module = load_module()
        master = matrix_target(module, "macos", "macos")
        simulator = matrix_target(
            module,
            "simulator",
            "ios_simulator",
            capture_enabled=False,
        )
        rotation = module.MatrixRotation(master=master, clients=[simulator])
        events: list[tuple[str, int]] = []

        def fake_wait_connected_clients(master_target, *, expected_count, timeout):
            events.append((master_target.device_id, expected_count))
            return {"connectedClientCount": expected_count}

        module.wait_connected_clients = fake_wait_connected_clients
        module.collect_target_logs = lambda _rotation_dir, _targets, _states: {}

        with tempfile.TemporaryDirectory(prefix="hydracam_role_switch_only_") as tmp:
            result = module.run_role_switch_only_flow(
                rotation,
                Path(tmp),
                timeout=10,
            )

        self.assertEqual(events, [("macos", 1)])
        self.assertEqual(result["status"], "passed")
        self.assertTrue(result["roleSwitchOnly"])
        self.assertNotIn("take_photo", result)
        self.assertEqual(
            [entry["status"] for entry in result["targetResults"]],
            ["role_switched", "role_switched"],
        )

    def test_parse_devicectl_process_ids_reads_running_processes(self) -> None:
        module = load_module()

        process_ids = module.parse_devicectl_process_ids(
            {
                "result": {
                    "runningProcesses": [
                        {"processIdentifier": 1234},
                        {"pid": 5678},
                        {"processIdentifier": "not-an-int"},
                    ],
                },
            }
        )

        self.assertEqual(process_ids, [1234, 5678])


if __name__ == "__main__":
    unittest.main()
