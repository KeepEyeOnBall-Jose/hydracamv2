#!/usr/bin/env python3
"""Tests for the Android single-device capture profile runner."""

from __future__ import annotations

import argparse
import tempfile
import unittest
from pathlib import Path

import run_android_capture_profile as capture_profile


class AndroidCaptureProfileRunnerTests(unittest.TestCase):
    def test_build_apk_passes_automation_and_extra_dart_defines(self) -> None:
        commands: list[list[str]] = []
        original_run = capture_profile.run

        def fake_run(command, **_kwargs):
            commands.append(list(command))

        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp) / "app-debug.apk"
            apk.write_bytes(b"apk")
            args = argparse.Namespace(
                apk=apk,
                build=True,
                build_timeout=300,
                dart_define=[
                    "HYDRACAM_USE_MEDIA_TIMELINE_BRIDGE=true",
                    "HYDRACAM_MEDIA_TIMELINE_API_BASE_URL=http://192.168.1.20:3001/api",
                ],
            )
            capture_profile.run = fake_run
            try:
                result = capture_profile.build_apk(args)
            finally:
                capture_profile.run = original_run

        self.assertEqual(result, apk)
        self.assertEqual(len(commands), 1)
        self.assertIn("--dart-define=HYDRACAM_AUTOMATION=true", commands[0])
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

        with self.assertRaisesRegex(ValueError, "KEY=VALUE"):
            capture_profile.validated_dart_defines(args)


if __name__ == "__main__":
    unittest.main()
