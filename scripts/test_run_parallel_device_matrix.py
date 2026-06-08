#!/usr/bin/env python3
"""Tests for the parallel HydraCam device matrix runner."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import subprocess
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).with_name("run_parallel_device_matrix.py")

FLUTTER_DEVICES_OUTPUT = """Found 9 connected devices:
  SM G960F (mobile)            • 29d816ac550b7ece                         • android-arm64  • Android 10 (API 29)
  SM G935F (mobile)            • 9885e6503930304946                       • android-arm64  • Android 8.0.0 (API 26)
  SM G970F (mobile)            • RF8M21J8XRT                              • android-arm64  • Android 12 (API 31)
  SM G970F (mobile)            • RF8M90QE7LX                              • android-arm64  • Android 12 (API 31)
  iPad (5) (mobile)            • 8b406aa5c597eab4c4dfd9908f4a09b10a89ec63 • ios            • iOS 15.6.1 19G82
  Jose's iPhone (mobile)       • 00008101-000A68811E43001E                • ios            • iOS 26.5 23F77
  iPhone 16 Plus (mobile)      • 5CF4A12E-A8B5-4285-AE86-407B9067CB5F     • ios            • com.apple.CoreSimulator.SimRuntime.iOS-18-4 (simulator)
  macOS (desktop)              • macos                                    • darwin-arm64   • macOS 26.4.1 25E253 darwin-arm64
  Chrome (web)                 • chrome                                   • web-javascript • Google Chrome 148.0.7778.216
"""

ADB_DEVICES_OUTPUT = """List of devices attached
29d816ac550b7ece       device usb:0-1.3 product:starltexx model:SM_G960F device:starlte transport_id:2
9885e6503930304946     device usb:0-1.4 product:hero2ltexx model:SM_G935F device:hero2lte transport_id:7
RF8M21J8XRT            device usb:1-1 product:beyond0lteeea model:SM_G970F device:beyond0 transport_id:4
RF8M90QE7LX            device usb:0-1.2 product:beyond0lteeea model:SM_G970F device:beyond0 transport_id:6
"""


def load_module():
    spec = importlib.util.spec_from_file_location(
        "run_parallel_device_matrix",
        SCRIPT_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load run_parallel_device_matrix.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class ParallelDeviceMatrixTests(unittest.TestCase):
    def test_build_matrix_targets_excludes_chrome_and_marks_simulator_launch_only(self) -> None:
        module = load_module()

        targets = module.build_matrix_targets(
            FLUTTER_DEVICES_OUTPUT,
            ADB_DEVICES_OUTPUT,
            ios_hosts={
                "00008101-000A68811E43001E": "192.168.178.141",
                "8b406aa5c597eab4c4dfd9908f4a09b10a89ec63": "192.168.178.104",
            },
        )

        ids = [target.device_id for target in targets]
        self.assertNotIn("chrome", ids)
        self.assertIn("5CF4A12E-A8B5-4285-AE86-407B9067CB5F", ids)
        simulator = next(
            target
            for target in targets
            if target.device_id == "5CF4A12E-A8B5-4285-AE86-407B9067CB5F"
        )
        self.assertEqual(simulator.expected_result, "launch_only")
        self.assertFalse(simulator.capture_enabled)

    def test_physical_ios_targets_require_explicit_hosts(self) -> None:
        module = load_module()

        with self.assertRaisesRegex(module.MatrixConfigError, "Missing --ios-host"):
            module.build_matrix_targets(
                FLUTTER_DEVICES_OUTPUT,
                ADB_DEVICES_OUTPUT,
                ios_hosts={},
            )

    def test_target_filter_skips_unselected_physical_ios_host_requirement(self) -> None:
        module = load_module()

        targets = module.build_matrix_targets(
            FLUTTER_DEVICES_OUTPUT,
            ADB_DEVICES_OUTPUT,
            ios_hosts={},
            include_device_ids={"macos"},
        )

        self.assertEqual([target.device_id for target in targets], ["macos"])

    def test_allocates_unique_android_and_local_bridge_ports(self) -> None:
        module = load_module()

        targets = module.build_matrix_targets(
            FLUTTER_DEVICES_OUTPUT,
            ADB_DEVICES_OUTPUT,
            ios_hosts={
                "00008101-000A68811E43001E": "192.168.178.141",
                "8b406aa5c597eab4c4dfd9908f4a09b10a89ec63": "192.168.178.104",
            },
            android_port_base=6400,
            local_port_base=4770,
        )

        android_ports = [
            target.bridge_port for target in targets if target.platform == "android"
        ]
        local_ports = [
            target.bridge_port
            for target in targets
            if target.platform in {"macos", "ios_simulator"}
        ]
        self.assertEqual(android_ports, [6400, 6401, 6402, 6403])
        self.assertEqual(local_ports, [4770, 4771])
        self.assertEqual(len(android_ports + local_ports), len(set(android_ports + local_ports)))

    def test_s7_exynos_camera_timeout_is_classified_as_expected_blocker(self) -> None:
        module = load_module()

        classification = module.classify_known_blocker(
            "9885e6503930304946",
            "Camera2CameraImpl reopen failed\nExynosCamera3 wait timeout\n",
        )

        self.assertEqual(classification, "s7_exynos_camera_timeout")

    def test_dry_run_summary_records_shared_barrier(self) -> None:
        module = load_module()
        targets = module.build_matrix_targets(
            FLUTTER_DEVICES_OUTPUT,
            ADB_DEVICES_OUTPUT,
            ios_hosts={
                "00008101-000A68811E43001E": "192.168.178.141",
                "8b406aa5c597eab4c4dfd9908f4a09b10a89ec63": "192.168.178.104",
            },
        )

        summary = module.build_dry_run_summary(targets)

        self.assertTrue(summary["sharedBarrier"])
        self.assertEqual(summary["targetCount"], 8)
        self.assertEqual(summary["captureTargetCount"], 7)

    def test_flutter_launches_are_staged_until_each_bridge_is_healthy(self) -> None:
        module = load_module()
        events: list[tuple[str, str]] = []

        targets = [
            module.MatrixTarget(
                device_id="macos",
                label="macOS",
                platform="macos",
                runtime="macOS",
                lens="autoBack",
                profile="standard1080p30",
                host="127.0.0.1",
                bridge_port=4770,
                capture_enabled=True,
                expected_result="capture",
            ),
            module.MatrixTarget(
                device_id="simulator",
                label="Simulator",
                platform="ios_simulator",
                runtime="iOS simulator",
                lens="autoBack",
                profile="standard1080p30",
                host="127.0.0.1",
                bridge_port=4771,
                capture_enabled=False,
                expected_result="launch_only",
            ),
        ]

        class FakeProcess:
            pass

        def fake_launch_flutter(device_id, _log_path, *, port):
            events.append(("launch", f"{device_id}:{port}"))
            return FakeProcess()

        def fake_wait_for_bridge(bridge_url, _deadline):
            events.append(("wait", bridge_url))

        module.launch_flutter = fake_launch_flutter
        module.wait_for_bridge = fake_wait_for_bridge

        with tempfile.TemporaryDirectory(prefix="hydracam_parallel_launch_") as tmp:
            module.launch_flutter_targets(targets, Path(tmp), timeout=30)

        self.assertEqual(
            events,
            [
                ("launch", "macos:4770"),
                ("wait", "http://127.0.0.1:4770"),
                ("launch", "simulator:4771"),
                ("wait", "http://127.0.0.1:4771"),
            ],
        )

    def test_android_forward_cleanup_runs_per_serial(self) -> None:
        module = load_module()
        commands: list[list[str]] = []
        targets = [
            module.MatrixTarget(
                device_id="android-a",
                label="Android A",
                platform="android",
                runtime="Android",
                lens="autoBack",
                profile="standard1080p30",
                host="127.0.0.1",
                bridge_port=6400,
                capture_enabled=True,
                expected_result="capture",
            ),
            module.MatrixTarget(
                device_id="macos",
                label="macOS",
                platform="macos",
                runtime="macOS",
                lens="autoBack",
                profile="standard1080p30",
                host="127.0.0.1",
                bridge_port=4770,
                capture_enabled=True,
                expected_result="capture",
            ),
        ]

        def fake_run_command(command, **_kwargs):
            commands.append(list(command))

        module.run_command = fake_run_command

        module.remove_android_forwards(targets)

        self.assertEqual(
            commands,
            [["adb", "-s", "android-a", "forward", "--remove-all"]],
        )

    def test_build_android_apk_can_use_ndk_version_override(self) -> None:
        module = load_module()
        calls: list[tuple[list[str], dict]] = []

        def fake_run_command(command, **kwargs):
            calls.append((list(command), dict(kwargs)))

        module.run_command = fake_run_command

        module.build_android_apk(ndk_version="27.0.12077973")

        self.assertEqual(calls[0][0][:3], ["flutter", "build", "apk"])
        self.assertEqual(
            calls[0][1]["env_overrides"],
            {"ORG_GRADLE_PROJECT_hydracamNdkVersion": "27.0.12077973"},
        )

    def test_android_permissions_match_target_api_level(self) -> None:
        module = load_module()
        api_26 = module.MatrixTarget(
            device_id="s7",
            label="S7",
            platform="android",
            runtime="Android 8.0.0 (API 26)",
            lens="autoBack",
            profile="standard1080p30",
            host="127.0.0.1",
            bridge_port=6400,
            capture_enabled=True,
            expected_result="capture",
        )
        api_31 = module.dataclasses.replace(api_26, runtime="Android 12 (API 31)")
        api_33 = module.dataclasses.replace(api_26, runtime="Android 13 (API 33)")

        self.assertIn(
            "android.permission.WRITE_EXTERNAL_STORAGE",
            module.android_permissions_for_target(api_26),
        )
        self.assertIn(
            "android.permission.READ_EXTERNAL_STORAGE",
            module.android_permissions_for_target(api_31),
        )
        self.assertNotIn(
            "android.permission.WRITE_EXTERNAL_STORAGE",
            module.android_permissions_for_target(api_31),
        )
        self.assertNotIn(
            "android.permission.ACCESS_MEDIA_LOCATION",
            module.android_permissions_for_target(api_33),
        )
        self.assertEqual(
            [
                permission
                for permission in module.android_permissions_for_target(api_33)
                if permission.startswith("android.permission.READ_MEDIA_")
            ],
            [
                "android.permission.READ_MEDIA_IMAGES",
                "android.permission.READ_MEDIA_VIDEO",
            ],
        )

    def test_android_setup_stamps_launch_with_automation_target_id(self) -> None:
        module = load_module()
        target = module.MatrixTarget(
            device_id="android-a",
            label="Android A",
            platform="android",
            runtime="Android 12 (API 31)",
            lens="autoBack",
            profile="standard1080p30",
            host="127.0.0.1",
            bridge_port=6400,
            capture_enabled=True,
            expected_result="capture",
        )
        commands: list[list[str]] = []

        def fake_run_command(command, **_kwargs):
            commands.append(list(command))

        module.run_command = fake_run_command

        module.setup_android_target(target, Path("/tmp/app.apk"), skip_install=True)

        start_command = next(command for command in commands if "start" in command)
        self.assertIn("automationTargetId", start_command)
        self.assertIn("android-a", start_command)

    def test_android_logcat_collection_writes_failure_artifact(self) -> None:
        module = load_module()
        commands: list[list[str]] = []
        target = module.MatrixTarget(
            device_id="9885e6503930304946",
            label="S7",
            platform="android",
            runtime="Android",
            lens="autoBack",
            profile="standard1080p30",
            host="127.0.0.1",
            bridge_port=6401,
            capture_enabled=True,
            expected_result="capture",
            known_blocker="s7_exynos_camera_timeout",
        )

        def fake_run_command(command, **_kwargs):
            commands.append(list(command))
            return subprocess.CompletedProcess(
                command,
                0,
                stdout="ExynosCamera3 wait timeout\nCamera2CameraImpl reopen\n",
                stderr="",
            )

        module.run_command = fake_run_command

        with tempfile.TemporaryDirectory(prefix="hydracam_logcat_") as tmp:
            text = module.collect_android_logcat(target, Path(tmp), tail=123)
            artifact = Path(tmp) / "logcat-tail.txt"

            self.assertTrue(artifact.exists())
            self.assertIn("ExynosCamera3", text)

        self.assertEqual(
            commands,
            [["adb", "-s", "9885e6503930304946", "logcat", "-d", "-t", "123"]],
        )


if __name__ == "__main__":
    unittest.main()
