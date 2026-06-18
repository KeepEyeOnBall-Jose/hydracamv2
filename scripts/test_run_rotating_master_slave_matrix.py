#!/usr/bin/env python3
"""Tests for the rotating master/slave HydraCam matrix runner."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
import time
import zipfile
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

    def test_parse_args_accepts_expected_target_ids(self) -> None:
        module = load_module()

        args = module.parse_args([
            "--expect-target-id",
            "iphone",
            "--expect-target-id",
            "ipad",
        ])

        self.assertEqual(args.expect_target_id, ["iphone", "ipad"])

    def test_run_matrix_fails_fast_when_expected_target_is_absent(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_expected_missing_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {"android-a": "192.168.178.160"},
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                expect_target_id=["android-a", "iphone"],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=True,
                skip_build=False,
                skip_install=False,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=False,
                role_switch_only=False,
                collect_role_switch_logs=False,
                reuse_running_bridges=False,
                require_warm_bridges=False,
                fast_ios_launch=False,
                timeout=module.DEFAULT_TIMEOUT_SECONDS,
                standby_launch_timeout=None,
                role_switch_verify_timeout=(
                    module.DEFAULT_ROLE_SWITCH_VERIFY_TIMEOUT_SECONDS
                ),
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            module.adopt_running_bridge_ports = lambda targets, **_kwargs: list(targets)
            module.build_android_apk = (
                lambda *_args, **_kwargs: self.fail(
                    "build should not run when an expected target is absent"
                )
            )
            module.prepare_android_target = (
                lambda *_args, **_kwargs: self.fail(
                    "install should not run when an expected target is absent"
                )
            )
            module.launch_standby_targets = (
                lambda *_args, **_kwargs: self.fail(
                    "launch should not run when an expected target is absent"
                )
            )

            with self.assertRaisesRegex(module.MatrixRunError, "iphone"):
                module.run_matrix(args)

            preflight = module.json.loads(
                (tmp_path / "run" / "expected-targets.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(preflight["status"], "failed")
        self.assertEqual(preflight["expectedTargetIds"], ["android-a", "iphone"])
        self.assertEqual(preflight["selectedTargetIds"], ["android-a"])
        self.assertEqual(preflight["missingExpectedTargetIds"], ["iphone"])

    def test_run_matrix_records_expected_target_pass_when_present(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_expected_present_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {"android-a": "192.168.178.160"},
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                expect_target_id=["android-a"],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=True,
                skip_build=True,
                skip_install=True,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=True,
                role_switch_only=True,
                collect_role_switch_logs=False,
                reuse_running_bridges=True,
                require_warm_bridges=True,
                fast_ios_launch=False,
                timeout=1,
                role_switch_verify_timeout=1,
                max_set_role_request_start_skew_ms=10,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            exit_code = module.run_matrix(args)
            preflight = module.json.loads(
                (tmp_path / "run" / "expected-targets.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(preflight["status"], "passed")
        self.assertEqual(preflight["expectedTargetIds"], ["android-a"])
        self.assertEqual(preflight["selectedTargetIds"], ["android-a"])
        self.assertEqual(preflight["missingExpectedTargetIds"], [])

    def test_immediate_role_switch_auto_uses_latest_warm_summary_cache(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_latest_cache_") as tmp:
            tmp_path = Path(tmp)
            latest = tmp_path / "latest-warm-summary.json"
            latest.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "macos",
                                "label": "macOS",
                                "platform": "macos",
                                "runtime": "macOS",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:4762",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {"macos": "192.168.178.10"},
                    }
                ),
                encoding="utf-8",
            )
            args = module.parse_args([
                "--immediate-role-switch",
                "--dry-run",
                "--latest-warm-summary",
                str(latest),
                "--run-dir",
                str(tmp_path / "run"),
            ])

            module.discover_targets = (
                lambda *_args, **_kwargs: self.fail(
                    "discovery should not run when the latest warm cache exists"
                )
            )
            module.adopt_running_bridge_ports = (
                lambda targets, **_kwargs: list(targets)
            )

            def fake_adopt_ios(targets, adopted_args, _run_dir):
                self.assertFalse(adopted_args.auto_ios_bridge_hosts)
                return list(targets), {}

            module.adopt_running_ios_bridge_hosts = fake_adopt_ios

            exit_code = module.run_matrix(args)
            source = module.json.loads(
                (tmp_path / "run" / "warm-summary-source.json").read_text(
                    encoding="utf-8",
                )
            )
            summary = module.json.loads(
                (tmp_path / "run" / "summary.json").read_text(encoding="utf-8")
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(source["status"], "used")
        self.assertEqual(source["mode"], "auto_latest")
        self.assertEqual(summary["targets"][0]["deviceId"], "macos")

    def test_immediate_role_switch_falls_back_to_discovery_when_auto_cache_missing(
        self,
    ) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_latest_cache_missing_") as tmp:
            tmp_path = Path(tmp)
            args = module.parse_args([
                "--immediate-role-switch",
                "--dry-run",
                "--latest-warm-summary",
                str(tmp_path / "missing-latest.json"),
                "--run-dir",
                str(tmp_path / "run"),
            ])
            macos = matrix_target(module, "macos", "macos")
            calls = {"discover": 0}

            module.prefill_ios_hosts_from_running_bridges = (
                lambda *_args, **_kwargs: None
            )
            module.discover_targets = lambda _args: (
                calls.__setitem__("discover", calls["discover"] + 1) or [macos]
            )
            module.adopt_running_bridge_ports = (
                lambda targets, **_kwargs: list(targets)
            )
            module.adopt_running_ios_bridge_hosts = (
                lambda targets, _args, _run_dir: (list(targets), {})
            )

            exit_code = module.run_matrix(args)
            source = module.json.loads(
                (tmp_path / "run" / "warm-summary-source.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(calls["discover"], 1)
        self.assertEqual(source["status"], "not_used")
        self.assertEqual(source["reason"], "latest_warm_summary_missing")

    def test_explicit_latest_warm_summary_requires_cache_file(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_latest_cache_required_") as tmp:
            tmp_path = Path(tmp)
            args = module.parse_args([
                "--immediate-role-switch",
                "--dry-run",
                "--use-latest-warm-summary",
                "--latest-warm-summary",
                str(tmp_path / "missing-latest.json"),
                "--run-dir",
                str(tmp_path / "run"),
            ])

            with self.assertRaisesRegex(module.MatrixConfigError, "Latest warm"):
                module.run_matrix(args)

    def test_successful_warm_role_switch_updates_latest_summary_cache(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_latest_cache_update_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            latest = tmp_path / "latest-warm-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "macos",
                                "label": "macOS",
                                "platform": "macos",
                                "runtime": "macOS",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:4762",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {"macos": "192.168.178.10"},
                    }
                ),
                encoding="utf-8",
            )
            args = module.parse_args([
                "--warm-summary",
                str(warm_summary),
                "--immediate-role-switch",
                "--latest-warm-summary",
                str(latest),
                "--run-dir",
                str(tmp_path / "run"),
            ])

            module.adopt_running_bridge_ports = (
                lambda targets, **_kwargs: list(targets)
            )
            module.adopt_running_ios_bridge_hosts = (
                lambda targets, _args, _run_dir: (list(targets), {})
            )
            module.missing_warm_runtime_bridges = lambda _targets: []
            module.require_warm_runtime_bridges = lambda _targets: None
            module.apply_runtime_role_switch = (
                lambda *_args, **_kwargs: module.RuntimeRoleSwitchResponses(
                    {"macos": {"status": "ok"}},
                    timings={
                        "macos": {
                            "batch": "parallel",
                            "startOffsetMs": 0,
                            "endOffsetMs": 1,
                            "durationMs": 1,
                        },
                    },
                )
            )
            module.wait_for_master_commands = lambda *_args, **_kwargs: None
            module.run_role_switch_only_flow = (
                lambda rotation, *_args, **_kwargs: {
                    **module.rotation_to_json(rotation),
                    "status": "passed",
                    "roleSwitchOnly": True,
                    "targetResults": [],
                    "failures": [],
                }
            )

            exit_code = module.run_matrix(args)
            cache = module.json.loads(latest.read_text(encoding="utf-8"))
            cache_artifact = module.json.loads(
                (tmp_path / "run" / "latest-warm-summary-cache.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(cache["schema"], "hydracam.rotatingMasterSlave.latestWarmSummary.v1")
        self.assertEqual(cache["targets"][0]["deviceId"], "macos")
        self.assertEqual(cache["masterHosts"], {"macos": "192.168.178.10"})
        self.assertEqual(cache_artifact["status"], "updated")

    def test_cache_update_without_configured_latest_path_is_skipped(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_no_latest_cache_") as tmp:
            tmp_path = Path(tmp)
            args = module.argparse.Namespace(update_latest_warm_summary=True)
            module.write_latest_warm_summary_cache(
                args,
                tmp_path / "run",
                targets=[matrix_target(module, "macos", "macos")],
                master_hosts={"macos": "192.168.178.10"},
                source_artifact=tmp_path / "run" / "summary.json",
            )
            artifact = module.json.loads(
                (tmp_path / "run" / "latest-warm-summary-cache.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(artifact["status"], "skipped")
        self.assertEqual(artifact["reason"], "latest_warm_summary_path_not_configured")

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

    def test_parse_args_immediate_role_switch_sets_warm_only_defaults(self) -> None:
        module = load_module()

        args = module.parse_args([
            "--warm-summary",
            "/tmp/summary.json",
            "--immediate-role-switch",
        ])

        self.assertTrue(args.runtime_role_switch)
        self.assertTrue(args.role_switch_only)
        self.assertTrue(args.reuse_running_bridges)
        self.assertTrue(args.require_warm_bridges)
        self.assertTrue(args.skip_build)
        self.assertTrue(args.skip_install)
        self.assertTrue(args.auto_ios_bridge_hosts)
        self.assertTrue(args.stage_slaves_after_master_ready)
        self.assertEqual(args.timeout, module.IMMEDIATE_ROLE_SWITCH_TIMEOUT_SECONDS)
        self.assertEqual(
            args.standby_launch_timeout,
            module.IMMEDIATE_STANDBY_LAUNCH_TIMEOUT_SECONDS,
        )
        self.assertEqual(
            args.role_switch_verify_timeout,
            module.IMMEDIATE_ROLE_SWITCH_VERIFY_TIMEOUT_SECONDS,
        )

    def test_parse_args_accepts_repeat_role_switch_cycles(self) -> None:
        module = load_module()

        args = module.parse_args([
            "--immediate-role-switch",
            "--repeat-role-switch-cycles",
            "5",
            "--max-set-role-request-start-skew-ms",
            "10",
        ])

        self.assertEqual(args.repeat_role_switch_cycles, 5)
        self.assertEqual(args.max_set_role_request_start_skew_ms, 10)
        self.assertTrue(args.stage_slaves_after_master_ready)
        self.assertTrue(args.runtime_role_switch)
        self.assertTrue(args.role_switch_only)
        self.assertTrue(args.auto_ios_bridge_hosts)

    def test_parse_args_immediate_role_switch_can_disable_auto_ios_hosts(self) -> None:
        module = load_module()

        args = module.parse_args([
            "--immediate-role-switch",
            "--no-auto-ios-bridge-hosts",
        ])

        self.assertFalse(args.auto_ios_bridge_hosts)

    def test_parse_args_immediate_role_switch_can_force_fully_parallel(self) -> None:
        module = load_module()

        args = module.parse_args([
            "--immediate-role-switch",
            "--fully-parallel-role-switch",
        ])

        self.assertTrue(args.fully_parallel_role_switch)
        self.assertFalse(args.stage_slaves_after_master_ready)

    def test_parse_args_immediate_role_switch_preserves_explicit_timeouts(self) -> None:
        module = load_module()

        args = module.parse_args([
            "--immediate-role-switch",
            "--timeout=12",
            "--standby-launch-timeout",
            "6",
            "--role-switch-verify-timeout",
            "4",
        ])

        self.assertEqual(args.timeout, 12)
        self.assertEqual(args.standby_launch_timeout, 6)
        self.assertEqual(args.role_switch_verify_timeout, 4)

    def test_parse_args_warm_prime_only_sets_reuse_without_build_install(self) -> None:
        module = load_module()

        args = module.parse_args(["--warm-prime-only"])

        self.assertTrue(args.runtime_role_switch)
        self.assertTrue(args.role_switch_only)
        self.assertTrue(args.reuse_running_bridges)
        self.assertTrue(args.skip_build)
        self.assertTrue(args.skip_install)

    def test_parse_args_prime_then_immediate_sets_combined_fast_defaults(self) -> None:
        module = load_module()

        args = module.parse_args(["--prime-then-immediate-role-switch"])

        self.assertTrue(args.runtime_role_switch)
        self.assertTrue(args.role_switch_only)
        self.assertTrue(args.reuse_running_bridges)
        self.assertTrue(args.require_warm_bridges)
        self.assertTrue(args.skip_build)
        self.assertTrue(args.skip_install)
        self.assertTrue(args.stage_slaves_after_master_ready)
        self.assertEqual(args.timeout, module.IMMEDIATE_ROLE_SWITCH_TIMEOUT_SECONDS)
        self.assertEqual(
            args.standby_launch_timeout,
            module.IMMEDIATE_STANDBY_LAUNCH_TIMEOUT_SECONDS,
        )
        self.assertEqual(
            args.role_switch_verify_timeout,
            module.IMMEDIATE_ROLE_SWITCH_VERIFY_TIMEOUT_SECONDS,
        )

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
        self.assertIn("automationTargetId", command)
        self.assertIn("android-a", command)

    def test_settings_snapshot_matching_payload_skips_expensive_post(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")
        payload = module.build_rotation_settings_payload(target, target)
        snapshot = {
            **payload,
            "videoCaptureTarget": "1080p at 30 fps",
        }

        self.assertTrue(module.settings_snapshot_matches_payload(snapshot, payload))

    def test_apply_rotation_settings_skips_post_when_settings_already_match(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")
        calls: list[tuple[str, str]] = []
        payload = module.build_rotation_settings_payload(target, target)

        def fake_request_json(_bridge_url, method, path, *args, **kwargs):
            calls.append((method, path))
            self.assertEqual(method, "GET")
            self.assertEqual(path, "/settings")
            return {
                **payload,
                "videoCaptureTarget": "1080p at 30 fps",
            }

        module.request_json = fake_request_json

        result = module.apply_rotation_settings(target, target)

        self.assertEqual(calls, [("GET", "/settings")])
        self.assertEqual(result["status"], "already_applied")

    def test_load_warm_summary_targets_rebuilds_targets_and_master_hosts(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_warm_summary_") as tmp:
            summary_path = Path(tmp) / "summary.json"
            summary_path.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                            {
                                "deviceId": "ipad",
                                "label": "iPad",
                                "platform": "ios_physical",
                                "runtime": "iOS 15.6.1",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://192.168.178.104:4762",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {
                            "android-a": "192.168.178.160",
                            "ipad": "192.168.178.104",
                        },
                    }
                ),
                encoding="utf-8",
            )

            targets, master_hosts = module.load_warm_summary_targets(summary_path)

        self.assertEqual([target.device_id for target in targets], ["android-a", "ipad"])
        self.assertEqual(targets[0].host, "127.0.0.1")
        self.assertEqual(targets[0].bridge_port, 6400)
        self.assertEqual(targets[1].host, "192.168.178.104")
        self.assertEqual(master_hosts["android-a"], "192.168.178.160")

    def test_load_warm_summary_targets_accepts_warm_prime_directory(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_warm_prime_summary_") as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "warm-bridge-prime.json").write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {"android-a": "192.168.178.160"},
                    }
                ),
                encoding="utf-8",
            )

            targets, master_hosts = module.load_warm_summary_targets(tmp_path)

        self.assertEqual([target.device_id for target in targets], ["android-a"])
        self.assertEqual(master_hosts, {"android-a": "192.168.178.160"})

    def test_run_matrix_uses_warm_summary_without_discovery(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_warm_run_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {"android-a": "192.168.178.160"},
                    }
                ),
                encoding="utf-8",
            )
            apk = tmp_path / "app.apk"
            apk.write_text("apk", encoding="utf-8")
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                skip_build=True,
                skip_install=True,
                apk=apk,
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=True,
                role_switch_only=True,
                collect_role_switch_logs=False,
                reuse_running_bridges=True,
                fast_ios_launch=False,
                timeout=1,
                role_switch_verify_timeout=1,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )
            events: list[str] = []

            def fail_discovery(_args):
                raise AssertionError("device discovery should be skipped")

            def fail_resolve_master_hosts(*_args, **_kwargs):
                raise AssertionError("master host probing should be skipped")

            module.discover_targets = fail_discovery
            module.resolve_master_hosts = fail_resolve_master_hosts
            module.prepare_android_target = lambda *_args, **_kwargs: events.append("prepare")
            module.launch_standby_targets = lambda *_args, **_kwargs: {}
            module.apply_runtime_role_switch = lambda *_args, **_kwargs: {"android-a": {"status": "ok"}}
            module.wait_for_master_commands = lambda *_args, **_kwargs: None
            module.run_role_switch_only_flow = (
                lambda rotation, *_args, **_kwargs: {
                    **module.rotation_to_json(rotation),
                    "status": "passed",
                    "roleSwitchOnly": True,
                    "targetResults": [],
                    "failures": [],
                }
            )

            exit_code = module.run_matrix(args)

        self.assertEqual(exit_code, 0)
        self.assertEqual(events, ["prepare"])

    def test_run_matrix_uses_short_role_switch_verification_timeout(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_fast_role_verify_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {"android-a": "192.168.178.160"},
                    }
                ),
                encoding="utf-8",
            )
            apk = tmp_path / "app.apk"
            apk.write_text("apk", encoding="utf-8")
            observed: dict[str, float] = {}
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                skip_build=True,
                skip_install=True,
                apk=apk,
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=True,
                role_switch_only=True,
                collect_role_switch_logs=False,
                reuse_running_bridges=True,
                fast_ios_launch=False,
                timeout=30,
                role_switch_verify_timeout=2,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            module.prepare_android_target = lambda *_args, **_kwargs: None
            module.launch_standby_targets = lambda *_args, **_kwargs: {}
            module.apply_runtime_role_switch = (
                lambda *_args, **_kwargs: {"android-a": {"status": "ok"}}
            )
            module.wait_for_master_commands = (
                lambda *_args, **kwargs: observed.setdefault(
                    "master_commands",
                    kwargs["timeout"],
                )
            )

            def fake_role_switch_only_flow(_rotation, _rotation_dir, **kwargs):
                observed["role_switch_only"] = kwargs["timeout"]
                return {
                    **module.rotation_to_json(_rotation),
                    "status": "passed",
                    "roleSwitchOnly": True,
                    "targetResults": [],
                    "failures": [],
                }

            module.run_role_switch_only_flow = fake_role_switch_only_flow

            exit_code = module.run_matrix(args)

        self.assertEqual(exit_code, 0)
        self.assertEqual(observed["master_commands"], 2)
        self.assertEqual(observed["role_switch_only"], 2)

    def test_run_matrix_repeats_hot_role_switch_cycles(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_repeat_role_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                            {
                                "deviceId": "macos",
                                "label": "macOS",
                                "platform": "macos",
                                "runtime": "macOS",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:4770",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {
                            "android-a": "192.168.178.160",
                            "macos": "127.0.0.1",
                        },
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                expect_target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=False,
                warm_prime_only=False,
                prime_then_immediate_role_switch=False,
                skip_build=True,
                skip_install=True,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=True,
                role_switch_only=True,
                repeat_role_switch_cycles=3,
                collect_role_switch_logs=False,
                reuse_running_bridges=True,
                require_warm_bridges=True,
                fast_ios_launch=False,
                xctrace_ios_launch=False,
                xctrace_time_limit_seconds=3600,
                timeout=1,
                standby_launch_timeout=None,
                role_switch_verify_timeout=1,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )
            switch_events: list[str] = []

            module.adopt_running_bridge_ports = (
                lambda targets, **_kwargs: list(targets)
            )
            module.bridge_supports_runtime_role_switch = lambda _target: True
            module.prepare_android_target = lambda *_args, **_kwargs: None

            def fail_launch(*_args, **_kwargs):
                raise AssertionError("hot repeat should reuse running bridges")

            module.launch_standby_targets = fail_launch

            def fake_apply_runtime_role_switch(rotation, *, targets, **_kwargs):
                switch_events.append(rotation.master.device_id)
                timings = {
                    target.device_id: {
                        "startOffsetMs": 0.0,
                        "endOffsetMs": 1.0,
                        "durationMs": 1.0,
                    }
                    for target in targets
                }
                return module.RuntimeRoleSwitchResponses(
                    {
                        target.device_id: {"status": "ok"}
                        for target in targets
                    },
                    timings=timings,
                )

            def fake_wait_for_master_commands(*_args, **_kwargs):
                time.sleep(0.001)

            def fake_wait_expected_connected_clients(rotation, **_kwargs):
                time.sleep(0.001)
                return {
                    "connectedClientCount": len(rotation.clients),
                    "connectedClients": [
                        {"deviceId": client.device_id}
                        for client in rotation.clients
                    ],
                }

            module.apply_runtime_role_switch = fake_apply_runtime_role_switch
            module.wait_for_master_commands = fake_wait_for_master_commands
            module.wait_expected_connected_clients = fake_wait_expected_connected_clients
            module.collect_target_logs = lambda _rotation_dir, _targets, _states: {}

            exit_code = module.run_matrix(args)
            summary = module.json.loads(
                (tmp_path / "run" / "summary.json").read_text(encoding="utf-8")
            )
            phase_file_exists = (
                tmp_path
                / "run"
                / "cycle-03"
                / "master-macos-macos"
                / "phase-timings.json"
            ).exists()

        self.assertEqual(exit_code, 0)
        self.assertEqual(summary["rotationCount"], 6)
        self.assertEqual(summary["repeatRoleSwitchCycles"], 3)
        self.assertEqual(
            [rotation["cycleNumber"] for rotation in summary["rotations"]],
            [1, 1, 2, 2, 3, 3],
        )
        self.assertEqual(
            switch_events,
            ["android-a", "macos", "android-a", "macos", "android-a", "macos"],
        )
        self.assertEqual(summary["phaseTimingStats"]["set_role"]["count"], 6)
        self.assertEqual(summary["phaseTimingStats"]["master_commands"]["count"], 6)
        self.assertEqual(summary["phaseTimingStats"]["connected_clients"]["count"], 6)
        self.assertEqual(
            summary["runtimeRoleSwitchTimingStats"]["requestStartSkewMs"]["count"],
            6,
        )
        self.assertEqual(
            summary["runtimeRoleSwitchTimingStats"]["requestStartSkewMs"]["maxMs"],
            0.0,
        )
        self.assertEqual(
            summary["runtimeRoleSwitchTimingStats"][
                "parallelRequestStartSkewMs"
            ]["maxMs"],
            0.0,
        )
        self.assertIn("elapsedSeconds", summary)
        self.assertTrue(phase_file_exists)

    def test_staged_role_switch_skips_duplicate_master_command_wait(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_staged_skip_wait_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                            {
                                "deviceId": "macos",
                                "label": "macOS",
                                "platform": "macos",
                                "runtime": "macOS",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:4770",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {
                            "android-a": "192.168.178.160",
                            "macos": "127.0.0.1",
                        },
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                expect_target_id=[],
                master_id=["android-a"],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=False,
                warm_prime_only=False,
                prime_then_immediate_role_switch=False,
                skip_build=True,
                skip_install=True,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=True,
                role_switch_only=True,
                repeat_role_switch_cycles=1,
                max_set_role_request_start_skew_ms=None,
                stage_slaves_after_master_ready=True,
                collect_role_switch_logs=False,
                reuse_running_bridges=True,
                require_warm_bridges=True,
                fast_ios_launch=False,
                xctrace_ios_launch=False,
                xctrace_time_limit_seconds=3600,
                timeout=1,
                standby_launch_timeout=None,
                role_switch_verify_timeout=1,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            module.adopt_running_bridge_ports = (
                lambda targets, **_kwargs: list(targets)
            )
            module.bridge_supports_runtime_role_switch = lambda _target: True
            module.prepare_android_target = lambda *_args, **_kwargs: None
            module.launch_standby_targets = lambda *_args, **_kwargs: {}

            def fake_apply_runtime_role_switch(rotation, *, targets, **kwargs):
                self.assertTrue(kwargs["stage_slaves_after_master_ready"])
                timings = {
                    target.device_id: {
                        "startOffsetMs": 0.0,
                        "endOffsetMs": 1.0,
                        "durationMs": 1.0,
                    }
                    for target in targets
                }
                return module.RuntimeRoleSwitchResponses(
                    {
                        target.device_id: {"status": "ok"}
                        for target in targets
                    },
                    timings=timings,
                    mode="master_ready_then_parallel_slaves",
                )

            def fail_wait_for_master_commands(*_args, **_kwargs):
                raise AssertionError("staged mode already waited for master commands")

            module.apply_runtime_role_switch = fake_apply_runtime_role_switch
            module.wait_for_master_commands = fail_wait_for_master_commands
            module.wait_expected_connected_clients = (
                lambda rotation, **_kwargs: {
                    "connectedClientCount": len(rotation.clients),
                    "connectedClients": [
                        {"deviceId": client.device_id}
                        for client in rotation.clients
                    ],
                }
            )
            module.collect_target_logs = lambda _rotation_dir, _targets, _states: {}

            exit_code = module.run_matrix(args)
            summary = module.json.loads(
                (tmp_path / "run" / "summary.json").read_text(encoding="utf-8")
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(summary["status"], "passed")
        self.assertNotIn("master_commands", summary["phaseTimingStats"])
        self.assertEqual(summary["phaseTimingStats"]["set_role"]["count"], 1)
        self.assertEqual(
            summary["phaseTimingStats"]["connected_clients"]["count"],
            1,
        )

    def test_direct_macos_bridge_port_uses_compiled_default(self) -> None:
        module = load_module()
        macos = module.dataclasses.replace(
            matrix_target(module, "macos", "macos"),
            bridge_port=4770,
        )
        android = matrix_target(module, "android-a", "android")

        normalized = module.normalize_direct_macos_bridge_ports([macos, android])

        self.assertEqual(normalized[0].device_id, "macos")
        self.assertEqual(normalized[0].bridge_port, module.DEFAULT_PORT)
        self.assertEqual(normalized[1].bridge_port, android.bridge_port)

    def test_run_matrix_fails_when_set_role_parallel_skew_exceeds_limit(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_skew_limit_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                            {
                                "deviceId": "macos",
                                "label": "macOS",
                                "platform": "macos",
                                "runtime": "macOS",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:4770",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {
                            "android-a": "192.168.178.160",
                            "macos": "127.0.0.1",
                        },
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                expect_target_id=[],
                master_id=["android-a"],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=False,
                warm_prime_only=False,
                prime_then_immediate_role_switch=False,
                skip_build=True,
                skip_install=True,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=True,
                role_switch_only=True,
                repeat_role_switch_cycles=1,
                collect_role_switch_logs=False,
                reuse_running_bridges=True,
                require_warm_bridges=True,
                fast_ios_launch=False,
                xctrace_ios_launch=False,
                xctrace_time_limit_seconds=3600,
                timeout=1,
                standby_launch_timeout=None,
                role_switch_verify_timeout=1,
                max_set_role_request_start_skew_ms=1,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            module.adopt_running_bridge_ports = (
                lambda targets, **_kwargs: list(targets)
            )
            module.bridge_supports_runtime_role_switch = lambda _target: True
            module.prepare_android_target = lambda *_args, **_kwargs: None
            module.launch_standby_targets = (
                lambda *_args, **_kwargs: self.fail(
                    "hot skew check should not launch standby"
                )
            )
            module.wait_for_master_commands = (
                lambda *_args, **_kwargs: self.fail(
                    "skew failure should stop before master command polling"
                )
            )

            def fake_apply_runtime_role_switch(_rotation, *, targets, **_kwargs):
                timings = {
                    targets[0].device_id: {
                        "startOffsetMs": 0.0,
                        "endOffsetMs": 3.0,
                        "durationMs": 3.0,
                    },
                    targets[1].device_id: {
                        "startOffsetMs": 5.0,
                        "endOffsetMs": 7.0,
                        "durationMs": 2.0,
                    },
                }
                return module.RuntimeRoleSwitchResponses(
                    {
                        target.device_id: {"status": "ok"}
                        for target in targets
                    },
                    timings=timings,
                )

            module.apply_runtime_role_switch = fake_apply_runtime_role_switch

            exit_code = module.run_matrix(args)
            summary = module.json.loads(
                (tmp_path / "run" / "summary.json").read_text(encoding="utf-8")
            )

        self.assertEqual(exit_code, 1)
        self.assertEqual(summary["status"], "failed")
        self.assertEqual(
            summary["runtimeRoleSwitchTimingStats"]["requestStartSkewMs"]["maxMs"],
            5.0,
        )
        self.assertIn("exceeded", summary["rotations"][0]["failures"][0])

    def test_run_matrix_rejects_repeat_cycles_outside_hot_role_switch(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_repeat_reject_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {"android-a": "192.168.178.160"},
                    }
                ),
                encoding="utf-8",
            )
            args = module.parse_args([
                "--warm-summary",
                str(warm_summary),
                "--run-dir",
                str(tmp_path / "run"),
                "--dry-run",
                "--repeat-role-switch-cycles",
                "2",
            ])

            with self.assertRaisesRegex(module.MatrixConfigError, "requires"):
                module.run_matrix(args)

    def test_run_matrix_uses_short_standby_launch_timeout(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_fast_standby_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {"android-a": "192.168.178.160"},
                    }
                ),
                encoding="utf-8",
            )
            apk = tmp_path / "app.apk"
            apk.write_text("apk", encoding="utf-8")
            observed: dict[str, float] = {}
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                skip_build=True,
                skip_install=True,
                apk=apk,
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=True,
                role_switch_only=True,
                collect_role_switch_logs=False,
                reuse_running_bridges=True,
                fast_ios_launch=False,
                timeout=30,
                standby_launch_timeout=5,
                role_switch_verify_timeout=2,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            module.prepare_android_target = lambda *_args, **_kwargs: None
            module.adopt_running_bridge_ports = lambda targets, **_kwargs: list(targets)

            def fake_launch_standby_targets(*_args, **kwargs):
                observed["standby"] = kwargs["timeout"]
                return {}

            module.launch_standby_targets = fake_launch_standby_targets
            module.apply_runtime_role_switch = (
                lambda *_args, **_kwargs: {"android-a": {"status": "ok"}}
            )
            module.wait_for_master_commands = (
                lambda *_args, **kwargs: observed.setdefault(
                    "master_commands",
                    kwargs["timeout"],
                )
            )
            module.run_role_switch_only_flow = (
                lambda rotation, *_args, **_kwargs: {
                    **module.rotation_to_json(rotation),
                    "status": "passed",
                    "roleSwitchOnly": True,
                    "targetResults": [],
                    "failures": [],
                }
            )

            exit_code = module.run_matrix(args)

        self.assertEqual(exit_code, 0)
        self.assertEqual(observed["standby"], 5)
        self.assertEqual(observed["master_commands"], 2)

    def test_run_matrix_require_warm_bridges_fails_before_launch(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_require_warm_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                            {
                                "deviceId": "ipad",
                                "label": "iPad",
                                "platform": "ios_physical",
                                "runtime": "iOS 15.6.1",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://192.168.178.104:4762",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {
                            "android-a": "192.168.178.160",
                            "ipad": "192.168.178.104",
                        },
                    }
                ),
                encoding="utf-8",
            )
            apk = tmp_path / "app.apk"
            apk.write_text("apk", encoding="utf-8")
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                skip_build=True,
                skip_install=True,
                apk=apk,
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=True,
                role_switch_only=True,
                collect_role_switch_logs=False,
                reuse_running_bridges=True,
                require_warm_bridges=True,
                fast_ios_launch=False,
                timeout=30,
                standby_launch_timeout=5,
                role_switch_verify_timeout=2,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            module.adopt_running_bridge_ports = lambda targets, **_kwargs: list(targets)
            module.bridge_supports_runtime_role_switch = (
                lambda target: target.device_id == "android-a"
            )
            module.prepare_android_target = (
                lambda *_args, **_kwargs: self.fail(
                    "prepare should not run when a required warm bridge is missing"
                )
            )
            module.launch_standby_targets = (
                lambda *_args, **_kwargs: self.fail(
                    "launch should not run when a required warm bridge is missing"
                )
            )

            with self.assertRaisesRegex(module.MatrixRunError, "ipad"):
                module.run_matrix(args)

            preflight = module.json.loads(
                (tmp_path / "run" / "warm-bridge-preflight.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(preflight["status"], "failed")
        self.assertEqual(preflight["missingWarmBridgeDeviceIds"], ["ipad"])

    def test_run_matrix_immediate_role_switch_fails_before_build_install_launch(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_immediate_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            }
                        ],
                        "masterHosts": {"android-a": "192.168.178.160"},
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=True,
                skip_build=False,
                skip_install=False,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=False,
                role_switch_only=False,
                collect_role_switch_logs=False,
                reuse_running_bridges=False,
                require_warm_bridges=False,
                fast_ios_launch=False,
                timeout=module.DEFAULT_TIMEOUT_SECONDS,
                standby_launch_timeout=None,
                role_switch_verify_timeout=(
                    module.DEFAULT_ROLE_SWITCH_VERIFY_TIMEOUT_SECONDS
                ),
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            module.adopt_running_bridge_ports = lambda targets, **_kwargs: list(targets)
            module.bridge_supports_runtime_role_switch = lambda _target: False
            module.build_android_apk = (
                lambda *_args, **_kwargs: self.fail(
                    "build should not run in immediate mode"
                )
            )
            module.prepare_android_target = (
                lambda *_args, **_kwargs: self.fail(
                    "install should not run in immediate mode"
                )
            )
            module.launch_standby_targets = (
                lambda *_args, **_kwargs: self.fail(
                    "launch should not run when a warm bridge is missing"
                )
            )

            with self.assertRaisesRegex(module.MatrixRunError, "android-a"):
                module.run_matrix(args)

            preflight = module.json.loads(
                (tmp_path / "run" / "warm-bridge-preflight.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertTrue(args.runtime_role_switch)
        self.assertTrue(args.role_switch_only)
        self.assertTrue(args.reuse_running_bridges)
        self.assertTrue(args.require_warm_bridges)
        self.assertTrue(args.skip_build)
        self.assertTrue(args.skip_install)
        self.assertEqual(preflight["status"], "failed")
        self.assertEqual(preflight["missingWarmBridgeDeviceIds"], ["android-a"])

    def test_run_matrix_warm_prime_only_launches_missing_without_build_install(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_warm_prime_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                            {
                                "deviceId": "ipad",
                                "label": "iPad",
                                "platform": "ios_physical",
                                "runtime": "iOS 15.6.1",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://192.168.178.104:4762",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {
                            "android-a": "192.168.178.160",
                            "ipad": "192.168.178.104",
                        },
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=False,
                warm_prime_only=True,
                skip_build=False,
                skip_install=False,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=False,
                role_switch_only=False,
                collect_role_switch_logs=False,
                reuse_running_bridges=False,
                require_warm_bridges=False,
                fast_ios_launch=False,
                xctrace_ios_launch=True,
                xctrace_time_limit_seconds=3600,
                timeout=30,
                standby_launch_timeout=5,
                role_switch_verify_timeout=2,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )
            ipad_warm = False
            launches: list[dict[str, object]] = []

            module.adopt_running_bridge_ports = lambda targets, **_kwargs: list(targets)

            def fake_bridge_supports(target):
                return target.device_id != "ipad" or ipad_warm

            def fake_launch_standby_targets(targets, _run_dir, **kwargs):
                nonlocal ipad_warm
                launches.append({
                    "targetIds": [target.device_id for target in targets],
                    "reuse": kwargs["reuse_running_bridges"],
                    "xctrace": kwargs["xctrace_ios_launch"],
                    "timeout": kwargs["timeout"],
                })
                ipad_warm = True
                return {}

            module.bridge_supports_runtime_role_switch = fake_bridge_supports
            module.launch_standby_targets = fake_launch_standby_targets
            module.build_android_apk = (
                lambda *_args, **_kwargs: self.fail(
                    "build should not run in warm-prime-only mode"
                )
            )
            module.prepare_android_target = (
                lambda *_args, **_kwargs: self.fail(
                    "install should not run in warm-prime-only mode"
                )
            )

            exit_code = module.run_matrix(args)
            prime = module.json.loads(
                (tmp_path / "run" / "warm-bridge-prime.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(exit_code, 0)
        self.assertTrue(args.skip_build)
        self.assertTrue(args.skip_install)
        self.assertEqual(prime["status"], "passed")
        self.assertEqual(prime["initialMissingWarmBridgeDeviceIds"], ["ipad"])
        self.assertEqual(prime["finalMissingWarmBridgeDeviceIds"], [])
        self.assertEqual(
            prime["masterHosts"],
            {
                "android-a": "192.168.178.160",
                "ipad": "192.168.178.104",
            },
        )
        self.assertEqual(launches, [{
            "targetIds": ["android-a", "ipad"],
            "reuse": True,
            "xctrace": True,
            "timeout": 5,
        }])

    def test_warm_prime_profile_install_happens_before_ios_launch(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_warm_prime_install_") as tmp:
            tmp_path = Path(tmp)
            app_path = tmp_path / "Runner.app"
            app_path.mkdir()
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "ipad",
                                "label": "iPad",
                                "platform": "ios_physical",
                                "runtime": "iOS 15.6.1",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://192.168.178.104:4762",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            }
                        ],
                        "masterHosts": {"ipad": "192.168.178.104"},
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=False,
                warm_prime_only=True,
                skip_build=False,
                skip_install=False,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=False,
                role_switch_only=False,
                collect_role_switch_logs=False,
                reuse_running_bridges=False,
                require_warm_bridges=False,
                fast_ios_launch=False,
                xctrace_ios_launch=True,
                xctrace_time_limit_seconds=3600,
                ios_profile_build_install=True,
                ios_profile_app=app_path,
                timeout=30,
                standby_launch_timeout=5,
                role_switch_verify_timeout=2,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )
            events: list[str] = []
            ipad_warm = False

            module.adopt_running_bridge_ports = lambda targets, **_kwargs: list(targets)
            module.build_ios_profile_app = lambda: events.append("build")
            module.install_ios_profile_app = (
                lambda *_args, **_kwargs: events.append("install")
            )

            def fake_bridge_supports(target):
                return target.device_id == "ipad" and ipad_warm

            def fake_launch_standby_targets(*_args, **_kwargs):
                nonlocal ipad_warm
                events.append("launch")
                ipad_warm = True
                return {}

            module.bridge_supports_runtime_role_switch = fake_bridge_supports
            module.launch_standby_targets = fake_launch_standby_targets

            exit_code = module.run_matrix(args)

        self.assertEqual(exit_code, 0)
        self.assertEqual(events, ["build", "install", "launch"])

    def test_warm_prime_retries_after_ios_profile_trust_error(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_warm_prime_trust_retry_") as tmp:
            tmp_path = Path(tmp)
            target = matrix_target(module, "ipad", "ios_physical")
            missing_entry = {
                "deviceId": "ipad",
                "platform": "ios_physical",
                "bridgeUrl": "http://192.168.178.104:4762",
            }
            missing_snapshots = [
                [missing_entry],
                [missing_entry],
                [],
            ]
            launch_dirs: list[str] = []

            def fake_missing(_targets):
                if missing_snapshots:
                    return missing_snapshots.pop(0)
                return []

            def fake_launch_standby_targets(_targets, run_dir, **_kwargs):
                launch_dirs.append(Path(run_dir).name)
                if len(launch_dirs) == 1:
                    raise module.ReproError("ios_profile_not_trusted")
                return {}

            module.missing_warm_runtime_bridges = fake_missing
            module.launch_standby_targets = fake_launch_standby_targets

            exit_code = module.warm_prime_runtime_bridges(
                [target],
                tmp_path,
                timeout=1,
                apk=tmp_path / "app.apk",
                fast_ios_launch=False,
                xctrace_ios_launch=True,
                xctrace_time_limit_seconds=3600,
                ios_profile_trust_retry_timeout=1,
                ios_profile_trust_retry_interval=0,
            )
            summary = module.json.loads(
                (tmp_path / "warm-bridge-prime.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(
            launch_dirs,
            [
                "warm-prime-launch",
                "warm-prime-launch-trust-retry-01",
            ],
        )
        self.assertEqual(summary["status"], "passed")
        self.assertEqual(
            summary["iosProfileTrustRetryAttempts"][0][
                "missingBeforeAttemptDeviceIds"
            ],
            ["ipad"],
        )
        self.assertEqual(
            summary["iosProfileTrustRetryAttempts"][0][
                "missingAfterAttemptDeviceIds"
            ],
            [],
        )

    def test_warm_prime_trust_retry_is_off_by_default(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_warm_prime_no_retry_") as tmp:
            tmp_path = Path(tmp)
            target = matrix_target(module, "ipad", "ios_physical")
            missing_entry = {
                "deviceId": "ipad",
                "platform": "ios_physical",
                "bridgeUrl": "http://192.168.178.104:4762",
            }
            launch_count = 0

            module.missing_warm_runtime_bridges = lambda _targets: [missing_entry]

            def fake_launch_standby_targets(*_args, **_kwargs):
                nonlocal launch_count
                launch_count += 1
                raise module.ReproError("ios_profile_not_trusted")

            module.launch_standby_targets = fake_launch_standby_targets

            exit_code = module.warm_prime_runtime_bridges(
                [target],
                tmp_path,
                timeout=1,
                apk=tmp_path / "app.apk",
                fast_ios_launch=False,
                xctrace_ios_launch=True,
                xctrace_time_limit_seconds=3600,
            )
            summary = module.json.loads(
                (tmp_path / "warm-bridge-prime.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(exit_code, 1)
        self.assertEqual(launch_count, 1)
        self.assertNotIn("iosProfileTrustRetryAttempts", summary)
        self.assertEqual(summary["deviceActions"][0]["code"], "ios_profile_not_trusted")

    def test_run_matrix_warm_prime_only_records_launch_error(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_warm_prime_error_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "ipad",
                                "label": "iPad",
                                "platform": "ios_physical",
                                "runtime": "iOS 15.6.1",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://192.168.178.104:4762",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            }
                        ],
                        "masterHosts": {"ipad": "192.168.178.104"},
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=False,
                warm_prime_only=True,
                skip_build=False,
                skip_install=False,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=False,
                role_switch_only=False,
                collect_role_switch_logs=False,
                reuse_running_bridges=False,
                require_warm_bridges=False,
                fast_ios_launch=False,
                xctrace_ios_launch=True,
                xctrace_time_limit_seconds=3600,
                timeout=30,
                standby_launch_timeout=5,
                role_switch_verify_timeout=2,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            module.adopt_running_bridge_ports = lambda targets, **_kwargs: list(targets)
            module.bridge_supports_runtime_role_switch = lambda _target: False
            module.launch_standby_targets = (
                lambda *_args, **_kwargs: (_ for _ in ()).throw(
                    module.ReproError("ios_profile_not_trusted")
                )
            )

            exit_code = module.run_matrix(args)
            prime = module.json.loads(
                (tmp_path / "run" / "warm-bridge-prime.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(exit_code, 1)
        self.assertEqual(prime["status"], "failed")
        self.assertEqual(prime["finalMissingWarmBridgeDeviceIds"], ["ipad"])
        self.assertIn("ios_profile_not_trusted", prime["launchError"])
        self.assertEqual(prime["deviceActions"][0]["deviceId"], "ipad")
        self.assertEqual(
            prime["deviceActions"][0]["code"],
            "ios_profile_not_trusted",
        )
        self.assertIn(
            "VPN & Device Management",
            prime["deviceActions"][0]["action"],
        )

    def test_warm_prime_ios_launch_without_bridge_action_is_specific(self) -> None:
        module = load_module()
        target = matrix_target(module, "ipad", "ios_physical")
        entry = {
            "deviceId": "ipad",
            "platform": "ios_physical",
            "bridgeUrl": "http://192.168.178.104:4762",
        }

        action = module._warm_prime_device_action(
            entry,
            target,
            (
                "Automation bridge did not become healthy for ipad at "
                "http://192.168.178.104:4762: connection refused"
            ),
        )

        self.assertEqual(action["code"], "ios_launch_no_bridge")
        self.assertIn("automation bridge never appeared", action["action"])

    def test_run_matrix_prime_then_immediate_primes_before_rotations(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_prime_then_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "android-a",
                                "label": "Android A",
                                "platform": "android",
                                "runtime": "Android 12",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://127.0.0.1:6400",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                            {
                                "deviceId": "ipad",
                                "label": "iPad",
                                "platform": "ios_physical",
                                "runtime": "iOS 15.6.1",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://192.168.178.104:4762",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            },
                        ],
                        "masterHosts": {
                            "android-a": "192.168.178.160",
                            "ipad": "192.168.178.104",
                        },
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=False,
                warm_prime_only=False,
                prime_then_immediate_role_switch=True,
                skip_build=False,
                skip_install=False,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=False,
                role_switch_only=False,
                collect_role_switch_logs=False,
                reuse_running_bridges=False,
                require_warm_bridges=False,
                fast_ios_launch=False,
                xctrace_ios_launch=True,
                xctrace_time_limit_seconds=3600,
                timeout=30,
                standby_launch_timeout=5,
                role_switch_verify_timeout=2,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )
            ipad_warm = False
            events: list[str] = []

            module.adopt_running_bridge_ports = lambda targets, **_kwargs: list(targets)

            def fake_bridge_supports(target):
                return target.device_id != "ipad" or ipad_warm

            def fake_launch_standby_targets(*_args, **_kwargs):
                nonlocal ipad_warm
                events.append("prime")
                ipad_warm = True
                return {}

            module.bridge_supports_runtime_role_switch = fake_bridge_supports
            module.prepare_android_target = lambda *_args, **_kwargs: events.append("prepare")
            module.launch_standby_targets = fake_launch_standby_targets
            module.apply_runtime_role_switch = (
                lambda *_args, **_kwargs: {"android-a": {"status": "ok"}}
            )
            module.wait_for_master_commands = lambda *_args, **_kwargs: events.append("verify")
            module.run_role_switch_only_flow = (
                lambda rotation, *_args, **_kwargs: {
                    **module.rotation_to_json(rotation),
                    "status": "passed",
                    "roleSwitchOnly": True,
                    "targetResults": [],
                    "failures": [],
                }
            )

            exit_code = module.run_matrix(args)
            prime = module.json.loads(
                (tmp_path / "run" / "warm-bridge-prime.json").read_text(
                    encoding="utf-8",
                )
            )
            preflight = module.json.loads(
                (tmp_path / "run" / "warm-bridge-preflight.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(exit_code, 0)
        self.assertTrue(args.skip_build)
        self.assertTrue(args.skip_install)
        self.assertEqual(prime["initialMissingWarmBridgeDeviceIds"], ["ipad"])
        self.assertEqual(prime["finalMissingWarmBridgeDeviceIds"], [])
        self.assertEqual(preflight["status"], "passed")
        self.assertIn("prime", events)
        self.assertIn("verify", events)

    def test_run_matrix_prime_then_immediate_stops_when_prime_fails(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_prime_then_fail_") as tmp:
            tmp_path = Path(tmp)
            warm_summary = tmp_path / "previous-summary.json"
            warm_summary.write_text(
                module.json.dumps(
                    {
                        "targets": [
                            {
                                "deviceId": "ipad",
                                "label": "iPad",
                                "platform": "ios_physical",
                                "runtime": "iOS 15.6.1",
                                "lens": "autoBack",
                                "profile": "standard1080p30",
                                "bridgeUrl": "http://192.168.178.104:4762",
                                "captureEnabled": True,
                                "expectedResult": "capture",
                                "knownBlocker": None,
                            }
                        ],
                        "masterHosts": {"ipad": "192.168.178.104"},
                    }
                ),
                encoding="utf-8",
            )
            args = module.argparse.Namespace(
                warm_summary=warm_summary,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                immediate_role_switch=False,
                warm_prime_only=False,
                prime_then_immediate_role_switch=True,
                skip_build=False,
                skip_install=False,
                apk=tmp_path / "missing.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=False,
                role_switch_only=False,
                collect_role_switch_logs=False,
                reuse_running_bridges=False,
                require_warm_bridges=False,
                fast_ios_launch=False,
                xctrace_ios_launch=True,
                xctrace_time_limit_seconds=3600,
                timeout=30,
                standby_launch_timeout=5,
                role_switch_verify_timeout=2,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
            )

            module.adopt_running_bridge_ports = lambda targets, **_kwargs: list(targets)
            module.bridge_supports_runtime_role_switch = lambda _target: False
            module.launch_standby_targets = (
                lambda *_args, **_kwargs: (_ for _ in ()).throw(
                    module.ReproError("ios_profile_not_trusted")
                )
            )
            module.apply_runtime_role_switch = (
                lambda *_args, **_kwargs: self.fail(
                    "rotations should not run after failed warm-prime"
                )
            )

            exit_code = module.run_matrix(args)
            prime = module.json.loads(
                (tmp_path / "run" / "warm-bridge-prime.json").read_text(
                    encoding="utf-8",
                )
            )
            preflight_exists = (
                tmp_path / "run" / "warm-bridge-preflight.json"
            ).exists()

        self.assertEqual(exit_code, 1)
        self.assertEqual(prime["status"], "failed")
        self.assertIn("ios_profile_not_trusted", prime["launchError"])
        self.assertFalse(preflight_exists)

    def test_prepare_android_target_reuses_healthy_bridge_without_adb_calls(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")
        commands: list[list[str]] = []

        def fake_run_command(command, **_kwargs):
            commands.append(list(command))

        module.run_command = fake_run_command
        module.bridge_supports_runtime_role_switch = lambda _target: True

        module.prepare_android_target(
            target,
            Path("/tmp/app.apk"),
            skip_install=True,
            reuse_running_bridge=True,
        )

        self.assertEqual(commands, [])

    def test_prepare_android_target_reports_install_timeout(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")
        calls: list[tuple[list[str], dict]] = []

        def fake_run_command(command, **kwargs):
            calls.append((list(command), dict(kwargs)))
            if "install" in command:
                raise subprocess.TimeoutExpired(command, kwargs.get("timeout"))

        module.run_command = fake_run_command
        module.bridge_supports_runtime_role_switch = lambda _target: False

        with self.assertRaisesRegex(
            module.MatrixRunError,
            "Timed out installing Android APK on android-a",
        ):
            module.prepare_android_target(
                target,
                Path("/tmp/app.apk"),
                skip_install=False,
                reuse_running_bridge=False,
            )

        self.assertEqual(
            calls[0][1]["timeout"],
            module.ANDROID_ADB_INSTALL_TIMEOUT_SECONDS,
        )

    def test_prepare_android_target_reports_forward_timeout(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")
        calls: list[tuple[list[str], dict]] = []

        def fake_run_command(command, **kwargs):
            calls.append((list(command), dict(kwargs)))
            if "forward" in command:
                raise subprocess.TimeoutExpired(command, kwargs.get("timeout"))

        module.run_command = fake_run_command
        module.bridge_supports_runtime_role_switch = lambda _target: False

        with self.assertRaisesRegex(
            module.MatrixRunError,
            "Timed out forwarding Android automation port for android-a",
        ):
            module.prepare_android_target(
                target,
                Path("/tmp/app.apk"),
                skip_install=True,
                reuse_running_bridge=False,
            )

        self.assertEqual(
            calls[0][1]["timeout"],
            module.ANDROID_ADB_FORWARD_TIMEOUT_SECONDS,
        )

    def test_prepare_android_target_continues_when_permission_grant_times_out(
        self,
    ) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")
        calls: list[tuple[list[str], dict]] = []

        def fake_run_command(command, **kwargs):
            calls.append((list(command), dict(kwargs)))
            if "pm" in command and "grant" in command:
                raise subprocess.TimeoutExpired(command, kwargs.get("timeout"))

        module.run_command = fake_run_command
        module.bridge_supports_runtime_role_switch = lambda _target: False
        module.android_permissions_for_target = lambda _target: [
            "android.permission.CAMERA"
        ]

        module.prepare_android_target(
            target,
            Path("/tmp/app.apk"),
            skip_install=True,
            reuse_running_bridge=False,
        )

        permission_call = calls[-1]
        self.assertIn("grant", permission_call[0])
        self.assertEqual(
            permission_call[1]["timeout"],
            module.ANDROID_ADB_SETUP_TIMEOUT_SECONDS,
        )

    def test_stop_android_target_continues_when_force_stop_times_out(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")

        def fake_run_command(command, **kwargs):
            raise subprocess.TimeoutExpired(command, kwargs.get("timeout"))

        module.run_command = fake_run_command

        module.stop_android_target(target)

    def test_launch_android_target_reports_launch_timeout(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")
        module.stop_android_target = lambda _target: None
        module.build_android_start_command = lambda _target, *, role, master_ip: [
            "adb",
            "shell",
            "am",
            "start",
        ]

        def fake_run_command(command, **kwargs):
            raise subprocess.TimeoutExpired(command, kwargs.get("timeout"))

        module.run_command = fake_run_command

        with self.assertRaises(module.MatrixRunError) as context:
            module.launch_android_target(target, role="master", master_ip=None)

        self.assertIn("Timed out launching Android target", str(context.exception))

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
        repeated_summary = module.build_dry_run_summary(
            targets,
            rotations,
            runtime_role_switch=True,
            role_switch_only=True,
            repeat_role_switch_cycles=4,
        )

        self.assertEqual(summary["rotationCount"], 3)
        self.assertEqual(repeated_summary["rotationCount"], 12)
        self.assertEqual(repeated_summary["repeatRoleSwitchCycles"], 4)
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

    def test_flutter_target_launch_stops_process_when_bridge_wait_fails(self) -> None:
        module = load_module()
        target = matrix_target(module, "ipad", "ios_physical")
        events: list[str] = []

        class FakeProcess:
            pass

        process = FakeProcess()

        def fake_launch_flutter(*_args, **_kwargs):
            events.append("launch")
            return process

        def fake_wait_for_flutter_bridge(*_args, **_kwargs):
            events.append("wait")
            raise module.ReproError("no bridge")

        def fake_stop_flutter(received_process):
            self.assertIs(received_process, process)
            events.append("stop")

        module.launch_flutter = fake_launch_flutter
        module.wait_for_flutter_bridge = fake_wait_for_flutter_bridge
        module.stop_flutter = fake_stop_flutter

        with self.assertRaisesRegex(module.ReproError, "no bridge"):
            module.launch_flutter_target(
                target,
                Path("/tmp/hydracam-rotation"),
                role="standby",
                master_ip=None,
                timeout=10,
            )

        self.assertEqual(events, ["launch", "wait", "stop"])

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
                "HYDRACAM_AUTOMATION_TARGET_ID": "iphone",
            },
        )
        self.assertEqual(command[-1], module.IOS_BUNDLE_ID)

    def test_build_ios_xctrace_launch_command_passes_runtime_role_environment(self) -> None:
        module = load_module()
        target = matrix_target(module, "ipad", "ios_physical")
        output = Path("/tmp/hydracam.trace")

        command = module.build_ios_xctrace_launch_command(
            target,
            role="slave",
            master_ip="192.168.178.153",
            output=output,
            time_limit_seconds=3600,
        )

        self.assertEqual(command[:5], [
            "xcrun",
            "xctrace",
            "record",
            "--template",
            "Time Profiler",
        ])
        self.assertIn("--device", command)
        self.assertIn("ipad", command)
        self.assertIn("--time-limit", command)
        self.assertIn("3600s", command)
        self.assertIn("--output", command)
        self.assertIn(str(output), command)
        self.assertIn("--env", command)
        self.assertIn("HYDRACAM_AUTOMATION_ROLE=slave", command)
        self.assertIn(
            "HYDRACAM_AUTOMATION_TARGET_ID=ipad",
            command,
        )
        self.assertIn(
            "HYDRACAM_AUTOMATION_MASTER_IP=192.168.178.153",
            command,
        )
        self.assertIn("HYDRACAM_AUTOMATION_FORCE_SLAVE=true", command)
        self.assertEqual(command[-2:], ["--", module.IOS_BUNDLE_ID])

    def test_xctrace_launch_error_classifies_untrusted_profile(self) -> None:
        module = load_module()
        stderr = (
            "Unable to launch com.keepeyeonball because it has "
            "an invalid code signature, inadequate entitlements or its profile "
            "has not been explicitly trusted by the user."
        )

        message = module.classify_ios_xctrace_launch_error(stderr)

        self.assertIn("ios_profile_not_trusted", message)
        self.assertIn("trust", message.lower())

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
            {
                "HYDRACAM_AUTOMATION_ROLE": "standby",
                "HYDRACAM_AUTOMATION_TARGET_ID": "iphone",
            },
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
                "ackMode": "accepted",
            },
        )
        self.assertEqual(payloads["macos"]["role"], "slave")
        self.assertEqual(payloads["macos"]["ackMode"], "accepted")

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
            (
                "http://127.0.0.1:6400",
                "set_role",
                {"role": "master"},
            ),
            calls,
        )

    def test_bridge_supports_runtime_role_switch_requires_set_role_command(self) -> None:
        module = load_module()
        target = matrix_target(module, "ipad", "ios_physical")

        def fake_request_json(_bridge_url, _method, _path, *, timeout):
            return {
                "status": "ok",
                "commands": ["set_role"],
                "automationTargetId": "ipad",
            }

        module.request_json = fake_request_json

        self.assertTrue(module.bridge_supports_runtime_role_switch(target))

    def test_bridge_reuse_requires_matching_automation_target_id(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")

        def fake_request_json(_bridge_url, _method, _path, *, timeout):
            return {
                "status": "ok",
                "commands": ["set_role"],
                "automationTargetId": "android-b",
            }

        module.request_json = fake_request_json

        self.assertFalse(module.bridge_supports_runtime_role_switch(target))

    def test_bridge_reuse_rejects_missing_automation_target_id(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")

        def fake_request_json(_bridge_url, _method, _path, *, timeout):
            return {"status": "ok", "commands": ["set_role"]}

        module.request_json = fake_request_json

        self.assertFalse(module.bridge_supports_runtime_role_switch(target))

    def test_bridge_reuse_does_not_accept_bridge_without_set_role(self) -> None:
        module = load_module()
        target = matrix_target(module, "ipad", "ios_physical")

        def fake_request_json(_bridge_url, _method, _path, *, timeout):
            return {"status": "ok", "commands": ["take_photo"]}

        module.request_json = fake_request_json

        self.assertFalse(module.bridge_supports_runtime_role_switch(target))

    def test_launch_standby_targets_reuses_healthy_running_bridge(self) -> None:
        module = load_module()
        ipad = matrix_target(module, "ipad", "ios_physical")
        macos = matrix_target(module, "macos", "macos")
        macos = module.dataclasses.replace(macos, bridge_port=6401)
        events: list[tuple[str, str]] = []

        def fake_request_json(bridge_url, _method, _path, *, timeout):
            if bridge_url == ipad.bridge_url:
                return {
                    "status": "ok",
                    "commands": ["set_role"],
                    "automationTargetId": "ipad",
                }
            raise module.ReproError("not running")

        def fake_launch_target(target, _run_dir, *, role, master_ip, timeout, **_kwargs):
            events.append((target.device_id, role))
            return None

        def fake_wait_for_target_bridge(target, _deadline):
            events.append(("wait", target.bridge_url))

        module.request_json = fake_request_json
        module.launch_target = fake_launch_target
        module.wait_for_target_bridge = fake_wait_for_target_bridge

        with tempfile.TemporaryDirectory(prefix="hydracam_reuse_bridge_") as tmp:
            module.launch_standby_targets(
                [ipad, macos],
                Path(tmp),
                timeout=10,
                fast_ios_launch=False,
                reuse_running_bridges=True,
            )

        self.assertEqual(events[0], ("macos", "standby"))
        self.assertNotIn(("ipad", "standby"), events)
        self.assertIn(("wait", ipad.bridge_url), events)
        self.assertIn(("wait", macos.bridge_url), events)

    def test_macos_standby_non_default_port_uses_direct_launch(self) -> None:
        module = load_module()
        macos = matrix_target(module, "macos", "macos")
        macos = module.dataclasses.replace(macos, bridge_port=4770)
        events: list[str] = []

        def fake_launch_macos_standby_target(*_args, **_kwargs):
            events.append("direct")
            return None

        def fake_launch_flutter_target(*_args, **_kwargs):
            events.append("flutter")
            return None

        module.launch_macos_standby_target = fake_launch_macos_standby_target
        module.launch_flutter_target = fake_launch_flutter_target

        module.launch_target(
            macos,
            Path("/tmp/hydracam-rotation"),
            role="standby",
            master_ip=None,
            timeout=10,
        )

        self.assertEqual(events, ["direct"])

    def test_ios_physical_xctrace_launch_mode_uses_xctrace(self) -> None:
        module = load_module()
        ipad = matrix_target(module, "ipad", "ios_physical")
        events: list[str] = []

        def fake_launch_ios_xctrace_target(*_args, **_kwargs):
            events.append("xctrace")
            return None

        def fake_launch_ios_fast_target(*_args, **_kwargs):
            events.append("devicectl")
            return None

        def fake_launch_flutter_target(*_args, **_kwargs):
            events.append("flutter")
            return None

        module.launch_ios_xctrace_target = fake_launch_ios_xctrace_target
        module.launch_ios_fast_target = fake_launch_ios_fast_target
        module.launch_flutter_target = fake_launch_flutter_target

        module.launch_target(
            ipad,
            Path("/tmp/hydracam-rotation"),
            role="standby",
            master_ip=None,
            timeout=10,
            xctrace_ios_launch=True,
            xctrace_time_limit_seconds=3600,
        )

        self.assertEqual(events, ["xctrace"])

    def test_ios_physical_fast_launch_falls_back_to_xctrace_when_enabled(self) -> None:
        module = load_module()
        ipad = matrix_target(module, "ipad", "ios_physical")
        events: list[str] = []

        def fake_launch_ios_fast_target(*_args, **_kwargs):
            events.append("devicectl")
            raise module.ReproError("devicectl unavailable")

        def fake_launch_ios_xctrace_target(*_args, **_kwargs):
            events.append("xctrace")
            return None

        module.launch_ios_fast_target = fake_launch_ios_fast_target
        module.launch_ios_xctrace_target = fake_launch_ios_xctrace_target

        module.launch_target(
            ipad,
            Path("/tmp/hydracam-rotation"),
            role="standby",
            master_ip=None,
            timeout=10,
            fast_ios_launch=True,
            xctrace_ios_launch=True,
            xctrace_time_limit_seconds=3600,
        )

        self.assertEqual(events, ["devicectl", "xctrace"])

    def test_macos_standby_direct_launch_detaches_process_group(self) -> None:
        module = load_module()
        macos = matrix_target(module, "macos", "macos")
        captured: dict[str, object] = {}

        class FakeProcess:
            pass

        def fake_popen(command, **kwargs):
            captured["command"] = command
            captured.update(kwargs)
            return FakeProcess()

        with tempfile.TemporaryDirectory(prefix="hydracam_macos_launch_") as tmp:
            tmp_path = Path(tmp)
            binary = tmp_path / "HydraCam"
            binary.write_text("binary", encoding="utf-8")
            module.MACOS_DEBUG_BINARY = binary
            original_popen = module.subprocess.Popen
            try:
                module.subprocess.Popen = fake_popen
                module.wait_for_target_bridge = (
                    lambda target, _deadline: captured.setdefault(
                        "waited_for",
                        target.device_id,
                    )
                )

                process = module.launch_macos_standby_target(
                    macos,
                    tmp_path,
                    timeout=10,
                )
            finally:
                module.subprocess.Popen = original_popen
                for key in ("stdout", "stderr"):
                    stream = captured.get(key)
                    if hasattr(stream, "close"):
                        stream.close()

        self.assertIsInstance(process, FakeProcess)
        self.assertEqual(captured["command"], [str(binary)])
        self.assertTrue(captured["start_new_session"])
        self.assertIs(captured["stdin"], module.subprocess.PIPE)
        self.assertEqual(captured["env"]["HYDRACAM_AUTOMATION_ROLE"], "standby")
        self.assertEqual(captured["env"]["HYDRACAM_AUTOMATION_TARGET_ID"], "macos")
        self.assertEqual(captured["waited_for"], "macos")

    def test_adopt_running_bridge_ports_reuses_identity_matched_android_port(self) -> None:
        module = load_module()
        g960f = module.dataclasses.replace(
            matrix_target(module, "29d816ac550b7ece", "android"),
            bridge_port=6400,
        )
        s7 = module.dataclasses.replace(
            matrix_target(module, module.S7_SERIAL, "android"),
            bridge_port=6401,
        )
        rf8 = module.dataclasses.replace(
            matrix_target(module, "RF8M90QE7LX", "android"),
            bridge_port=6402,
        )

        def fake_request_json(bridge_url, _method, _path, *, timeout):
            if bridge_url == "http://127.0.0.1:6400":
                return {
                    "status": "ok",
                    "automationTargetId": "29d816ac550b7ece",
                    "commands": ["set_role"],
                }
            if bridge_url == "http://127.0.0.1:6401":
                return {
                    "status": "ok",
                    "automationTargetId": "RF8M90QE7LX",
                    "commands": ["set_role"],
                }
            raise module.ReproError("not running")

        module.request_json = fake_request_json

        adopted = module.adopt_running_bridge_ports(
            [g960f, s7, rf8],
            android_port_base=6400,
            local_port_base=4770,
        )

        by_id = {target.device_id: target.bridge_port for target in adopted}
        self.assertEqual(by_id["29d816ac550b7ece"], 6400)
        self.assertEqual(by_id["RF8M90QE7LX"], 6401)
        self.assertEqual(by_id[module.S7_SERIAL], 6402)

    def test_adopt_running_bridge_ports_reuses_macos_default_port(self) -> None:
        module = load_module()
        macos = module.dataclasses.replace(
            matrix_target(module, "macos", "macos"),
            bridge_port=4770,
        )

        def fake_request_json(bridge_url, _method, _path, *, timeout):
            if bridge_url == "http://127.0.0.1:4762":
                return {
                    "status": "ok",
                    "automationTargetId": "macos",
                    "commands": ["set_role"],
                }
            raise module.ReproError("not running")

        module.request_json = fake_request_json

        adopted = module.adopt_running_bridge_ports(
            [macos],
            android_port_base=6400,
            local_port_base=4770,
        )

        self.assertEqual(adopted[0].bridge_port, 4762)

    def test_adopt_running_bridge_ports_preserves_single_cold_macos_port(
        self,
    ) -> None:
        module = load_module()
        macos = module.dataclasses.replace(
            matrix_target(module, "macos", "macos"),
            bridge_port=4770,
        )
        module.request_json = (
            lambda *_args, **_kwargs: (_ for _ in ()).throw(
                module.ReproError("not running"),
            )
        )

        adopted = module.adopt_running_bridge_ports(
            [macos],
            android_port_base=6400,
            local_port_base=4770,
        )

        self.assertEqual(adopted[0].bridge_port, 4770)

    def test_wait_for_flutter_bridge_requires_matching_target_identity(self) -> None:
        module = load_module()
        target = matrix_target(module, "ipad", "ios_physical")
        calls = 0

        class FakeProcess:
            def poll(self):
                return None

        def fake_request_json(_bridge_url, _method, _path, *, timeout):
            nonlocal calls
            calls += 1
            if calls == 1:
                return {
                    "status": "ok",
                    "automationTargetId": "stale-android",
                    "commands": ["set_role"],
                }
            return {
                "status": "ok",
                "automationTargetId": "ipad",
                "commands": ["set_role"],
            }

        sleep_intervals: list[float] = []
        module.request_json = fake_request_json
        module.time.sleep = lambda interval: sleep_intervals.append(interval)

        module.wait_for_flutter_bridge(target, FakeProcess(), time.time() + 5)

        self.assertEqual(calls, 2)
        self.assertEqual(sleep_intervals, [1])

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

    def test_apply_runtime_role_switch_records_parallel_request_timings(self) -> None:
        module = load_module()
        master = matrix_target(module, "android-a", "android")
        iphone = matrix_target(module, "iphone", "ios_physical")
        macos = matrix_target(module, "macos", "macos")
        rotation = module.MatrixRotation(master=master, clients=[iphone, macos])

        def fake_post_command(_bridge_url, _command, payload, _deadline):
            time.sleep(0.1)
            return {"result": payload}

        module.post_command = fake_post_command

        responses = module.apply_runtime_role_switch(
            rotation,
            targets=[master, iphone, macos],
            master_host="192.168.178.153",
            timeout=10,
        )

        self.assertEqual(set(responses.timings), {"android-a", "iphone", "macos"})
        start_offsets = [
            timing["startOffsetMs"]
            for timing in responses.timings.values()
        ]
        self.assertLess(max(start_offsets) - min(start_offsets), 80)
        self.assertTrue(
            all(timing["durationMs"] >= 90 for timing in responses.timings.values())
        )

    def test_apply_runtime_role_switch_can_stage_slaves_after_master_ready(self) -> None:
        module = load_module()
        master = matrix_target(module, "android-a", "android")
        iphone = matrix_target(module, "iphone", "ios_physical")
        macos = matrix_target(module, "macos", "macos")
        rotation = module.MatrixRotation(master=master, clients=[iphone, macos])
        events: list[str] = []

        def fake_post_command(bridge_url, _command, payload, _deadline):
            role = payload["role"]
            if role == "master":
                events.append("post-master")
                return {"bridgeUrl": bridge_url, "role": role}
            events.append(f"post-slave-{bridge_url.rsplit(':', 1)[-1]}")
            time.sleep(0.05)
            return {"bridgeUrl": bridge_url, "role": role}

        def fake_wait_for_master_commands(_master, *, timeout):
            events.append(f"wait-master-{timeout}")
            time.sleep(0.02)

        module.post_command = fake_post_command
        module.wait_for_master_commands = fake_wait_for_master_commands

        responses = module.apply_runtime_role_switch(
            rotation,
            targets=[master, iphone, macos],
            master_host="192.168.178.153",
            timeout=10,
            stage_slaves_after_master_ready=True,
            master_ready_timeout=2,
        )
        snapshot = module.build_runtime_role_switch_snapshot(
            responses,
            started_at="2026-06-07T17:34:19.000000",
            elapsed_seconds=0.1,
        )

        self.assertEqual(events[:2], ["post-master", "wait-master-2"])
        self.assertEqual(
            {timing["batch"] for timing in responses.timings.values()},
            {"master", "slaves"},
        )
        self.assertEqual(snapshot["mode"], "master_ready_then_parallel_slaves")
        self.assertGreater(snapshot["requestStartSkewMs"], 0)
        self.assertLess(snapshot["parallelRequestStartSkewMs"], 80)

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

    def test_build_runtime_role_switch_snapshot_records_request_skew(self) -> None:
        module = load_module()
        responses = module.RuntimeRoleSwitchResponses(
            {"macos": {"status": "ok"}, "android-a": {"status": "ok"}},
            timings={
                "macos": {
                    "startOffsetMs": 1.0,
                    "endOffsetMs": 30.0,
                    "durationMs": 29.0,
                },
                "android-a": {
                    "startOffsetMs": 3.5,
                    "endOffsetMs": 40.0,
                    "durationMs": 36.5,
                },
            },
        )

        snapshot = module.build_runtime_role_switch_snapshot(
            responses,
            started_at="2026-06-07T17:34:19.000000",
            elapsed_seconds=0.045,
        )

        self.assertEqual(snapshot["requestStartSkewMs"], 2.5)
        self.assertEqual(snapshot["requestEndSkewMs"], 10.0)
        self.assertEqual(snapshot["maxRequestDurationMs"], 36.5)
        self.assertEqual(
            snapshot["requestTimings"]["android-a"]["startOffsetMs"],
            3.5,
        )

    def test_build_connected_client_registration_timing_stats(self) -> None:
        module = load_module()

        stats = module.build_connected_client_registration_timing_stats([
            {
                "runtimeRoleSwitch": {
                    "startedAt": "2026-06-07T12:00:00.000000",
                },
                "connectedClientsSnapshot": {
                    "masterServerStartedAt": "2026-06-07T12:00:00.050000",
                    "connectedClients": [
                        {
                            "deviceId": "client-a",
                            "registeredAt": "2026-06-07T12:00:00.100000",
                        },
                        {
                            "deviceId": "client-b",
                            "registeredAt": "2026-06-07T12:00:00.180000",
                        },
                    ],
                },
            },
        ])

        self.assertEqual(stats["masterServerStartLagMs"]["maxMs"], 50.0)
        self.assertEqual(stats["latestClientRegistrationLagMs"]["maxMs"], 180.0)
        self.assertEqual(
            stats["maxClientRegistrationAfterServerStartMs"]["maxMs"],
            130.0,
        )

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

        def fake_wait_expected_connected_clients(
            received_rotation,
            *,
            master_hosts,
            timeout,
        ):
            events.append((
                received_rotation.master.device_id,
                len(received_rotation.clients),
            ))
            return {"connectedClientCount": expected_count}

        expected_count = 1
        module.wait_expected_connected_clients = fake_wait_expected_connected_clients
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

    def test_role_switch_only_flow_skips_logs_on_success_by_default(self) -> None:
        module = load_module()
        master = matrix_target(module, "macos", "macos")
        android = matrix_target(module, "android-a", "android")
        rotation = module.MatrixRotation(master=master, clients=[android])
        log_calls: list[str] = []

        module.wait_expected_connected_clients = (
            lambda *_args, **_kwargs: {"connectedClientCount": 1}
        )

        def fake_collect_target_logs(_rotation_dir, _targets, _states):
            log_calls.append("called")
            return {}

        module.collect_target_logs = fake_collect_target_logs

        with tempfile.TemporaryDirectory(prefix="hydracam_role_no_logs_") as tmp:
            result = module.run_role_switch_only_flow(
                rotation,
                Path(tmp),
                timeout=10,
            )

        self.assertEqual(result["status"], "passed")
        self.assertEqual(log_calls, [])

    def test_role_switch_only_flow_records_phase_timing(self) -> None:
        module = load_module()
        master = matrix_target(module, "macos", "macos")
        android = matrix_target(module, "android-a", "android")
        rotation = module.MatrixRotation(master=master, clients=[android])
        phase_timings: dict[str, object] = {}

        def fake_wait_expected_connected_clients(*_args, **_kwargs):
            time.sleep(0.01)
            return {"connectedClientCount": 1}

        module.wait_expected_connected_clients = fake_wait_expected_connected_clients
        module.collect_target_logs = lambda _rotation_dir, _targets, _states: {}

        with tempfile.TemporaryDirectory(prefix="hydracam_role_timing_") as tmp:
            result = module.run_role_switch_only_flow(
                rotation,
                Path(tmp),
                timeout=10,
                phase_timings=phase_timings,
            )

        self.assertEqual(result["status"], "passed")
        self.assertIn("connected_clients", result["phaseTimings"])
        self.assertIn("connected_clients", phase_timings)
        self.assertGreaterEqual(
            result["phaseTimings"]["connected_clients"]["durationMs"],
            1,
        )

    def test_role_switch_only_flow_rejects_wrong_connected_client_ip(self) -> None:
        module = load_module()
        master = matrix_target(module, "macos", "macos")
        android = matrix_target(module, "android-a", "android")
        rotation = module.MatrixRotation(master=master, clients=[android])

        def fake_post_command(_bridge_url, command, _payload, _deadline):
            self.assertEqual(command, "connected_clients")
            return {
                "result": {
                    "connectedClientCount": 1,
                    "connectedClients": [
                        {"remoteIp": "192.168.178.104"},
                    ],
                },
            }

        module.post_command = fake_post_command
        module.collect_target_logs = lambda _rotation_dir, _targets, _states: {}

        with tempfile.TemporaryDirectory(prefix="hydracam_wrong_client_") as tmp:
            result = module.run_role_switch_only_flow(
                rotation,
                Path(tmp),
                timeout=0.01,
                master_hosts={"android-a": "192.168.178.160"},
            )

        self.assertEqual(result["status"], "failed")
        self.assertIn("192.168.178.160", result["failures"][0])
        self.assertIn("192.168.178.104", result["failures"][0])

    def test_wait_expected_connected_clients_polls_subsecond(self) -> None:
        module = load_module()
        master = matrix_target(module, "macos", "macos")
        android = module.dataclasses.replace(
            matrix_target(module, "android-a", "android"),
            host="192.168.178.160",
        )
        rotation = module.MatrixRotation(master=master, clients=[android])
        calls = 0
        sleep_intervals: list[float] = []

        def fake_post_command(_bridge_url, command, _payload, _deadline):
            nonlocal calls
            calls += 1
            self.assertEqual(command, "connected_clients")
            if calls == 1:
                return {
                    "result": {
                        "connectedClientCount": 0,
                        "connectedClients": [],
                    }
                }
            return {
                "result": {
                    "connectedClientCount": 1,
                    "connectedClients": [{"remoteIp": "192.168.178.160"}],
                }
            }

        module.post_command = fake_post_command
        module.time.sleep = lambda interval: sleep_intervals.append(interval)

        result = module.wait_expected_connected_clients(
            rotation,
            master_hosts={"android-a": "192.168.178.160"},
            timeout=3,
        )

        self.assertEqual(result["connectedClientCount"], 1)
        self.assertTrue(sleep_intervals)
        self.assertLessEqual(max(sleep_intervals), 0.2)

    def test_wait_for_master_commands_polls_subsecond(self) -> None:
        module = load_module()
        target = matrix_target(module, "android-a", "android")
        calls = 0
        sleep_intervals: list[float] = []

        def fake_request_json(_bridge_url, _method, _path, *, timeout):
            nonlocal calls
            calls += 1
            if calls < 3:
                return {
                    "status": "ok",
                    "automationTargetId": "android-a",
                    "commands": ["set_role"],
                }
            return {
                "status": "ok",
                "automationTargetId": "android-a",
                "commands": ["set_role", "connected_clients"],
            }

        module.request_json = fake_request_json
        module.time.sleep = lambda interval: sleep_intervals.append(interval)

        module.wait_for_master_commands(target, timeout=3)

        self.assertEqual(calls, 3)
        self.assertTrue(sleep_intervals)
        self.assertLessEqual(max(sleep_intervals), 0.2)

    def test_capture_flow_rejects_wrong_connected_client_ip(self) -> None:
        module = load_module()
        master = matrix_target(module, "macos", "macos")
        android = matrix_target(module, "android-a", "android")
        rotation = module.MatrixRotation(master=master, clients=[android])

        def fake_post_command(_bridge_url, command, _payload, _deadline):
            if command == "connected_clients":
                return {
                    "result": {
                        "connectedClientCount": 1,
                        "connectedClients": [
                            {"remoteIp": "192.168.178.104"},
                        ],
                    },
                }
            return {"status": "ok", "command": command}

        module.post_command = fake_post_command
        module.apply_rotation_settings = lambda target, master: {"ok": True}
        module.wait_for_target_stage = (
            lambda targets, states, stage, predicate, *, timeout, required: {}
        )
        module.collect_target_logs = lambda _rotation_dir, _targets, _states: {}

        with tempfile.TemporaryDirectory(prefix="hydracam_capture_wrong_client_") as tmp:
            result = module.run_rotation_capture_flow(
                rotation,
                Path(tmp),
                record_seconds=0,
                timeout=0.01,
                master_hosts={"android-a": "192.168.178.160"},
            )

        self.assertEqual(result["status"], "failed")
        self.assertIn("192.168.178.160", result["failures"][0])
        self.assertIn("192.168.178.104", result["failures"][0])

    def test_capture_flow_uses_shorter_connected_client_timeout(self) -> None:
        module = load_module()
        master = matrix_target(module, "macos", "macos")
        android = matrix_target(module, "android-a", "android")
        rotation = module.MatrixRotation(master=master, clients=[android])
        observed_timeouts: list[float] = []

        def fake_wait_expected_connected_clients(
            _rotation,
            *,
            master_hosts,
            timeout,
        ):
            observed_timeouts.append(timeout)
            return {"connectedClientCount": 1, "connectedClients": []}

        module.wait_expected_connected_clients = fake_wait_expected_connected_clients
        module.apply_rotation_settings = lambda target, master: {"ok": True}
        module.post_command = lambda *_args, **_kwargs: {"status": "ok"}
        module.wait_for_target_stage = (
            lambda targets, states, stage, predicate, *, timeout, required: {}
        )
        module.collect_target_logs = lambda _rotation_dir, _targets, _states: {}

        with tempfile.TemporaryDirectory(prefix="hydracam_capture_timeout_") as tmp:
            module.run_rotation_capture_flow(
                rotation,
                Path(tmp),
                record_seconds=0,
                timeout=3,
                master_hosts={"android-a": "192.168.178.160"},
            )

        self.assertEqual(observed_timeouts, [3])

    def test_wait_for_target_stage_polls_targets_in_parallel(self) -> None:
        module = load_module()
        targets = [
            matrix_target(module, "android-a", "android"),
            matrix_target(module, "android-b", "android"),
            matrix_target(module, "macos", "macos"),
        ]
        states = {
            target.device_id: {
                "target": module.target_to_json(target),
                "failures": [],
                "knownBlocker": None,
            }
            for target in targets
        }

        def fake_await_rotation_session_value(target, _predicate, *, timeout):
            time.sleep(0.15)
            return {"deviceId": target.device_id, "ready": True}

        module.await_rotation_session_value = fake_await_rotation_session_value

        started = time.perf_counter()
        snapshots = module.wait_for_target_stage(
            targets,
            states,
            "stage",
            lambda payload: payload.get("ready") is True,
            timeout=5,
            required=lambda _target: True,
        )
        elapsed = time.perf_counter() - started

        self.assertLess(elapsed, 0.3)
        self.assertEqual(set(snapshots), {"android-a", "android-b", "macos"})
        self.assertFalse(any(state["failures"] for state in states.values()))

    def test_capture_flow_caps_recording_ready_wait(self) -> None:
        module = load_module()
        master = matrix_target(module, "macos", "macos")
        android = matrix_target(module, "android-a", "android")
        rotation = module.MatrixRotation(master=master, clients=[android])
        observed_timeouts: dict[str, float] = {}

        def fake_wait_for_target_stage(
            _targets,
            _states,
            stage,
            _predicate,
            *,
            timeout,
            required,
        ):
            observed_timeouts[stage] = timeout
            return {}

        module.wait_expected_connected_clients = (
            lambda *_args, **_kwargs: {"connectedClientCount": 1}
        )
        module.apply_rotation_settings = lambda target, master: {"ok": True}
        module.post_command = lambda *_args, **_kwargs: {"status": "ok"}
        module.wait_for_target_stage = fake_wait_for_target_stage
        module.collect_target_logs = lambda _rotation_dir, _targets, _states: {}

        with tempfile.TemporaryDirectory(prefix="hydracam_recording_ready_") as tmp:
            module.run_rotation_capture_flow(
                rotation,
                Path(tmp),
                record_seconds=0,
                timeout=60,
                master_hosts={"android-a": "192.168.178.160"},
            )

        self.assertEqual(
            observed_timeouts["start_recording"],
            module.DEFAULT_RECORDING_READY_TIMEOUT_SECONDS,
        )

    def test_capture_flow_uses_configurable_stage_timeouts(self) -> None:
        module = load_module()
        master = matrix_target(module, "macos", "macos")
        android = matrix_target(module, "android-a", "android")
        rotation = module.MatrixRotation(master=master, clients=[android])
        observed_timeouts: dict[str, float] = {}

        def fake_wait_for_target_stage(
            _targets,
            _states,
            stage,
            _predicate,
            *,
            timeout,
            required,
        ):
            observed_timeouts[stage] = timeout
            return {}

        module.wait_expected_connected_clients = (
            lambda *_args, **_kwargs: {"connectedClientCount": 1}
        )
        module.apply_rotation_settings = lambda target, master: {"ok": True}
        module.post_command = lambda *_args, **_kwargs: {"status": "ok"}
        module.wait_for_target_stage = fake_wait_for_target_stage
        module.collect_target_logs = lambda _rotation_dir, _targets, _states: {}

        with tempfile.TemporaryDirectory(prefix="hydracam_stage_timeout_") as tmp:
            module.run_rotation_capture_flow(
                rotation,
                Path(tmp),
                record_seconds=0,
                timeout=60,
                master_hosts={"android-a": "192.168.178.160"},
                capture_stage_timeout=7,
                recording_ready_timeout=5,
                stop_recording_timeout=9,
            )

        self.assertEqual(observed_timeouts["take_photo"], 7)
        self.assertEqual(observed_timeouts["start_recording"], 5)
        self.assertEqual(observed_timeouts["stop_recording"], 9)

    def test_parse_devicectl_process_ids_reads_running_processes(self) -> None:
        module = load_module()

        process_ids = module.parse_devicectl_process_ids(
            {
                "result": {
                    "runningProcesses": [
                        {
                            "processIdentifier": 1234,
                            "executable": (
                                "file:///private/var/containers/Bundle/"
                                "Application/UUID/Runner.app/Runner"
                            ),
                        },
                        {
                            "pid": 5678,
                            "executable": {
                                "path": (
                                    "/Users/jose/build/macos/HydraCam.app/"
                                    "HydraCam"
                                ),
                            },
                        },
                        {
                            "processIdentifier": 9012,
                            "executable": "file:///Applications/MobileSafari.app/MobileSafari",
                        },
                        {"processIdentifier": "not-an-int"},
                    ],
                },
            }
        )

        self.assertEqual(process_ids, [1234, 5678])

    def test_parse_arp_ipv4_hosts_extracts_unique_ipv4_values(self) -> None:
        module = load_module()

        hosts = module.parse_arp_ipv4_hosts(
            "? (192.168.178.168) at aa:bb on en0\n"
            "192.168.178.64 at cc:dd on en0\n"
            "? (192.168.178.168) at aa:bb on en0\n"
            "? (ff02::1) at <incomplete> on en0\n"
        )

        self.assertEqual(hosts, ["192.168.178.168", "192.168.178.64"])

    def test_prefill_ios_hosts_from_running_bridges_adds_identity_match(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_ios_prefill_") as tmp:
            tmp_path = Path(tmp)
            args = module.argparse.Namespace(
                auto_ios_bridge_hosts=True,
                ios_host=[],
                ios_bridge_scan_subnet=[],
                target_id=["iphone"],
                physical_ios_port=4762,
            )

            module.run_command = lambda *_args, **_kwargs: module.subprocess.CompletedProcess(
                args=[],
                returncode=0,
                stdout=(
                    "iPhone (mobile) • iphone • ios • iOS 26.5\n"
                    "iPhone 16 Plus (mobile) • sim • ios • simulator\n"
                ),
                stderr="",
            )
            module._candidate_ios_bridge_hosts = lambda *_args, **_kwargs: [
                "192.168.178.141",
                "192.168.178.168",
            ]
            module.discover_running_ios_bridge_hosts = (
                lambda device_ids, **_kwargs: {
                    "iphone": {
                        "deviceId": "iphone",
                        "host": "192.168.178.168",
                        "bridgeUrl": "http://192.168.178.168:4762",
                        "health": {
                            "status": "ok",
                            "automation": True,
                            "automationTargetId": "iphone",
                            "commands": ["set_role"],
                        },
                    }
                }
            )

            module.prefill_ios_hosts_from_running_bridges(args, tmp_path)
            artifact = module.json.loads(
                (tmp_path / "ios-bridge-host-prefill.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(args.ios_host, ["iphone=192.168.178.168"])
        self.assertEqual(artifact["status"], "passed")
        self.assertEqual(artifact["matchedIosHostDeviceIds"], ["iphone"])

    def test_prefill_ios_hosts_fast_launches_profile_when_bridge_is_cold(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_ios_prefill_launch_") as tmp:
            tmp_path = Path(tmp)
            args = module.argparse.Namespace(
                auto_ios_bridge_hosts=True,
                ios_host=[],
                ios_bridge_scan_subnet=[],
                target_id=["iphone"],
                physical_ios_port=4762,
                fast_ios_launch=True,
                warm_prime_only=False,
                prime_then_immediate_role_switch=True,
                standby_launch_timeout=1,
                timeout=1,
            )
            calls = {"scan": 0, "launch": 0}

            module.run_command = lambda *_args, **_kwargs: module.subprocess.CompletedProcess(
                args=[],
                returncode=0,
                stdout="iPhone (mobile) • iphone • ios • iOS 26.5\n",
                stderr="",
            )
            module._candidate_ios_bridge_hosts = lambda *_args, **_kwargs: [
                "192.168.178.168",
            ]

            def fake_discover(device_ids, **_kwargs):
                calls["scan"] += 1
                if calls["scan"] == 1:
                    return {}
                return {
                    "iphone": {
                        "deviceId": "iphone",
                        "host": "192.168.178.168",
                        "bridgeUrl": "http://192.168.178.168:4762",
                        "health": {
                            "status": "ok",
                            "automation": True,
                            "automationTargetId": "iphone",
                            "commands": ["set_role"],
                        },
                    }
                }

            def fake_launch(device, _args, _run_dir):
                calls["launch"] += 1
                return {
                    "deviceId": device.device_id,
                    "returnCode": 0,
                    "stdoutPath": "stdout",
                    "stderrPath": "stderr",
                }

            module.discover_running_ios_bridge_hosts = fake_discover
            module.fast_launch_ios_for_host_discovery = fake_launch

            module.prefill_ios_hosts_from_running_bridges(args, tmp_path)
            artifact = module.json.loads(
                (tmp_path / "ios-bridge-host-prefill.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(args.ios_host, ["iphone=192.168.178.168"])
        self.assertEqual(calls["launch"], 1)
        self.assertEqual(artifact["fastLaunchAttemptedDeviceIds"], ["iphone"])

    def test_adopt_running_ios_bridge_hosts_replaces_stale_identity_host(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_ios_adopt_") as tmp:
            tmp_path = Path(tmp)
            args = module.argparse.Namespace(
                auto_ios_bridge_hosts=True,
                ios_host=[],
                ios_bridge_scan_subnet=[],
                physical_ios_port=4762,
            )
            iphone = module.dataclasses.replace(
                matrix_target(module, "iphone", "ios_physical"),
                host="192.168.178.141",
                bridge_port=4762,
            )

            module._candidate_ios_bridge_hosts = lambda *_args, **_kwargs: [
                "192.168.178.141",
                "192.168.178.168",
            ]
            module.discover_running_ios_bridge_hosts = (
                lambda device_ids, **_kwargs: {
                    "iphone": {
                        "deviceId": "iphone",
                        "host": "192.168.178.168",
                        "bridgeUrl": "http://192.168.178.168:4762",
                        "health": {
                            "status": "ok",
                            "automation": True,
                            "automationTargetId": "iphone",
                            "commands": ["set_role"],
                        },
                    }
                }
            )

            updated, matches = module.adopt_running_ios_bridge_hosts(
                [iphone],
                args,
                tmp_path,
            )
            artifact = module.json.loads(
                (tmp_path / "ios-bridge-host-adoption.json").read_text(
                    encoding="utf-8",
                )
            )

        self.assertEqual(updated[0].host, "192.168.178.168")
        self.assertEqual(matches["iphone"]["host"], "192.168.178.168")
        self.assertEqual(
            artifact["targets"][0]["bridgeUrl"],
            "http://192.168.178.168:4762",
        )

    def test_ios_profile_build_install_builds_once_and_installs_each_ios_target(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_ios_profile_install_") as tmp:
            tmp_path = Path(tmp)
            app_path = tmp_path / "Runner.app"
            app_path.mkdir()
            args = module.argparse.Namespace(
                warm_summary=None,
                target_id=[],
                master_id=[],
                run_dir=tmp_path / "run",
                dry_run=False,
                skip_build=False,
                skip_install=False,
                apk=tmp_path / "app.apk",
                android_ndk_version=None,
                android_port_base=6400,
                local_port_base=4762,
                physical_ios_port=4762,
                macos_master_host=None,
                runtime_role_switch=True,
                role_switch_only=True,
                collect_role_switch_logs=False,
                reuse_running_bridges=True,
                require_warm_bridges=True,
                fast_ios_launch=True,
                xctrace_ios_launch=False,
                xctrace_time_limit_seconds=3600,
                ios_profile_build_install=True,
                ios_profile_app=app_path,
                timeout=1,
                role_switch_verify_timeout=1,
                record_seconds=0,
                capture_stage_timeout=1,
                recording_ready_timeout=1,
                stop_recording_timeout=1,
                repeat_role_switch_cycles=1,
                stage_slaves_after_master_ready=False,
                max_set_role_request_start_skew_ms=None,
                expected_target_id=[],
                standby_launch_timeout=1,
            )
            iphone = matrix_target(module, "iphone", "ios_physical")
            events: list[tuple[str, str]] = []

            module.discover_targets = lambda _args: [iphone]
            module.normalize_direct_macos_bridge_ports = lambda targets: list(targets)
            module.adopt_running_bridge_ports = lambda targets, *_args, **_kwargs: list(targets)
            module.require_expected_target_ids = lambda *_args, **_kwargs: None
            module.build_rotations = lambda targets: [
                module.MatrixRotation(master=targets[0], clients=[])
            ]
            module.build_ios_profile_app = lambda: events.append(("build", "ios"))
            module.install_ios_profile_app = (
                lambda target, _app_path, _run_dir: events.append(
                    ("install", target.device_id)
                )
            )
            module.missing_warm_runtime_bridges = lambda _targets: []
            module.require_warm_runtime_bridges = lambda _targets: None
            module.resolve_master_hosts = lambda targets, **_kwargs: {
                target.device_id: target.host for target in targets
            }
            module.launch_standby_targets = lambda *_args, **_kwargs: {}
            module.apply_runtime_role_switch = (
                lambda *_args, **_kwargs: {"iphone": {"status": "ok"}}
            )
            module.wait_for_master_commands = lambda *_args, **_kwargs: None
            module.run_role_switch_only_flow = (
                lambda rotation, *_args, **_kwargs: {
                    **module.rotation_to_json(rotation),
                    "status": "passed",
                    "roleSwitchOnly": True,
                    "targetResults": [],
                    "failures": [],
                }
            )

            exit_code = module.run_matrix(args)

        self.assertEqual(exit_code, 0)
        self.assertEqual(events, [("build", "ios"), ("install", "iphone")])

    def test_package_ios_profile_ipa_contains_payload_app(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_ios_profile_ipa_") as tmp:
            tmp_path = Path(tmp)
            app_path = tmp_path / "Runner.app"
            app_path.mkdir()
            (app_path / "Info.plist").write_text("plist", encoding="utf-8")

            ipa_path = module.package_ios_profile_ipa(
                app_path,
                tmp_path / "hydracam-profile.ipa",
            )

            with zipfile.ZipFile(ipa_path) as archive:
                names = set(archive.namelist())

        self.assertIn("Payload/Runner.app/Info.plist", names)

    def test_resolve_ios_profile_app_path_uses_profile_iphoneos_fallback(
        self,
    ) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_ios_profile_path_") as tmp:
            tmp_path = Path(tmp)
            old_default = tmp_path / "build" / "ios" / "iphoneos" / "Runner.app"
            new_default = (
                tmp_path / "build" / "ios" / "Profile-iphoneos" / "Runner.app"
            )
            new_default.mkdir(parents=True)
            module.IOS_PROFILE_APP = old_default
            module.IOS_PROFILE_APP_FALLBACKS = (new_default, old_default)

            resolved = module.resolve_ios_profile_app_path(old_default)

        self.assertEqual(resolved, new_default)

    def test_install_ios_profile_app_falls_back_to_flutter_install(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="hydracam_ios_profile_fallback_") as tmp:
            tmp_path = Path(tmp)
            app_path = tmp_path / "Runner.app"
            app_path.mkdir()
            (app_path / "Info.plist").write_text("plist", encoding="utf-8")
            run_dir = tmp_path / "run"
            target = matrix_target(module, "ipad", "ios_physical")
            commands: list[list[str]] = []

            def fake_run_command(command, **_kwargs):
                commands.append(list(command))
                if command[0:2] == ["xcrun", "devicectl"]:
                    raise subprocess.CalledProcessError(
                        1,
                        command,
                        output="devicectl stdout",
                        stderr="devicectl stderr",
                    )
                return subprocess.CompletedProcess(
                    command,
                    0,
                    stdout="flutter install stdout",
                    stderr="flutter install stderr",
                )

            module.run_command = fake_run_command

            module.install_ios_profile_app(target, app_path, run_dir)

            target_dir = run_dir / "ios-profile-install" / target.slug
            ipa_path = target_dir / "hydracam-profile.ipa"

            self.assertEqual(commands[0][0:2], ["xcrun", "devicectl"])
            self.assertEqual(commands[1][0:3], ["flutter", "install", "-d"])
            self.assertEqual(commands[1][-1], str(ipa_path))
            self.assertTrue(ipa_path.exists())
            self.assertEqual(
                (target_dir / "devicectl-install.stderr.txt").read_text(
                    encoding="utf-8",
                ),
                "devicectl stderr",
            )
            self.assertEqual(
                (target_dir / "flutter-install.stdout.txt").read_text(
                    encoding="utf-8",
                ),
                "flutter install stdout",
            )


if __name__ == "__main__":
    unittest.main()
