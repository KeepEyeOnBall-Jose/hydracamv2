#!/usr/bin/env python3
"""Tests for the iOS capture repro helper."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).with_name("ios_capture_repro.py")


def load_module():
    spec = importlib.util.spec_from_file_location("ios_capture_repro", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load ios_capture_repro.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class IosCaptureReproTests(unittest.TestCase):
    def test_flutter_launch_command_passes_requested_bridge_port(self) -> None:
        module = load_module()

        command = module.build_flutter_launch_command("macos", 4771)

        self.assertIn("--dart-define=HYDRACAM_AUTOMATION_PORT=4771", command)
        self.assertIn("--dart-define=HYDRACAM_AUTOMATION=true", command)
        self.assertIn("--dart-define=HYDRACAM_AUTOMATION_ROLE=master", command)
        self.assertIn(
            "--dart-define=HYDRACAM_AUTOMATION_TARGET_ID=macos",
            command,
        )

    def test_flutter_launch_command_can_force_slave_to_master_ip(self) -> None:
        module = load_module()

        command = module.build_flutter_launch_command(
            "00008101-000A68811E43001E",
            4762,
            role="slave",
            master_ip="192.168.178.141",
        )

        self.assertIn("--dart-define=HYDRACAM_AUTOMATION_ROLE=slave", command)
        self.assertIn(
            "--dart-define=HYDRACAM_AUTOMATION_MASTER_IP=192.168.178.141",
            command,
        )


if __name__ == "__main__":
    unittest.main()
