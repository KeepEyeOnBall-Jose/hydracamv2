#!/usr/bin/env python3
"""Tests for the Android hardware UI e2e runner."""

from __future__ import annotations

import argparse
import tempfile
import unittest
from pathlib import Path

import run_hardware_ui_e2e as hardware_ui


class HardwareUiE2ETests(unittest.TestCase):
    def test_parser_accepts_output_dir_alias_for_run_dir(self) -> None:
        parser = hardware_ui.build_arg_parser()

        args = parser.parse_args(
            [
                "--output-dir",
                "logs/verification-runs/example",
                "--route",
                "setup",
            ]
        )

        self.assertEqual(
            args.run_dir,
            Path("logs/verification-runs/example"),
        )
        self.assertEqual(args.route, ["setup"])

    def test_main_applies_default_routes_and_scroll_checks(self) -> None:
        parser = hardware_ui.build_arg_parser()
        args = parser.parse_args([])

        if not args.route:
            args.route = list(hardware_ui.DEFAULT_ROUTES)
        if args.no_scroll_checks:
            args.scroll_check_route = []
        elif not args.scroll_check_route:
            args.scroll_check_route = list(hardware_ui.DEFAULT_SCROLL_CHECK_ROUTES)

        self.assertEqual(args.route, ["setup", "standby"])
        self.assertEqual(args.scroll_check_route, ["setup"])

    def test_build_apk_passes_extra_dart_defines_to_flutter(self) -> None:
        commands: list[list[str]] = []
        original_run_command = hardware_ui.run_command

        def fake_run_command(command, **_kwargs):
            commands.append(list(command))

        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp) / "app-debug.apk"
            apk.write_bytes(b"apk")
            args = argparse.Namespace(
                apk=apk,
                skip_build=False,
                build_timeout=300,
                dev_auto_login=False,
                dev_auto_login_email=None,
                dev_auto_login_guid=None,
                dev_auto_login_profile_picture=None,
                dart_define=[
                    "HYDRACAM_USE_MEDIA_TIMELINE_BRIDGE=true",
                    "HYDRACAM_MEDIA_TIMELINE_API_BASE_URL=http://192.168.1.20:3001/api",
                ],
            )
            hardware_ui.run_command = fake_run_command
            try:
                result = hardware_ui.build_apk(args)
            finally:
                hardware_ui.run_command = original_run_command

        self.assertEqual(result, apk)
        self.assertEqual(len(commands), 1)
        self.assertIn(
            "--dart-define=HYDRACAM_USE_MEDIA_TIMELINE_BRIDGE=true",
            commands[0],
        )
        bridge_url_define = (
            "--dart-define=HYDRACAM_MEDIA_TIMELINE_API_BASE_URL="
            "http://192.168.1.20:3001/api"
        )
        self.assertIn(bridge_url_define, commands[0])

    def test_extra_dart_defines_must_use_key_value_syntax(self) -> None:
        args = argparse.Namespace(dart_define=["HYDRACAM_USE_MEDIA_TIMELINE_BRIDGE"])

        with self.assertRaisesRegex(
            hardware_ui.HardwareUiE2EError,
            "KEY=VALUE",
        ):
            hardware_ui.validated_dart_defines(args)


if __name__ == "__main__":
    unittest.main()
