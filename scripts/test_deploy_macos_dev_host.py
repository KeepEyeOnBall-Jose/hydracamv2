#!/usr/bin/env python3
"""Tests for the one-command macOS dev-host deploy wrapper."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).with_name("deploy_macos_dev_host.zsh")


@unittest.skipUnless(
    shutil.which("zsh"),
    "zsh is unavailable; deploy_macos_dev_host.zsh is a macOS dev-host wrapper",
)
class DeployMacosDevHostTests(unittest.TestCase):
    def test_help_documents_one_click_usage_and_validation_modes(self) -> None:
        result = subprocess.run(
            ["zsh", str(SCRIPT_PATH), "--help"],
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertIn("scripts/deploy_macos_dev_host.zsh jose@new-mac", result.stdout)
        self.assertIn("--password-file <file>", result.stdout)
        self.assertIn("--validation <quick|full|none>", result.stdout)

    def test_script_is_executable(self) -> None:
        mode = SCRIPT_PATH.stat().st_mode

        self.assertTrue(mode & stat.S_IXUSR)

    def test_static_contract_keeps_secret_and_build_outputs_out_of_rsync(self) -> None:
        source = SCRIPT_PATH.read_text(encoding="utf-8")

        self.assertIn("tempass.txt", source)
        self.assertIn(".git/", source)
        self.assertIn(".dart_tool/", source)
        self.assertIn("build/", source)
        self.assertIn("ios/Pods/", source)
        self.assertIn("macos/Pods/", source)
        self.assertIn("logs/verification-runs/", source)

    def test_static_contract_invokes_remote_bootstrap_and_debug_probe(self) -> None:
        source = SCRIPT_PATH.read_text(encoding="utf-8")

        self.assertIn("scripts/prepare_macos_dev_host.zsh", source)
        self.assertIn("flutter run -d macos --debug", source)
        self.assertIn("--dart-define=HYDRACAM_AUTOMATION=true", source)
        self.assertIn("--dart-define=HYDRACAM_AUTOMATION_ROLE=master", source)
        self.assertNotIn("HYDRACAM_AUTOMATION_ENABLED", source)
        self.assertNotIn("HYDRACAM_AUTOMATION_INITIAL_ROLE", source)
        self.assertIn("FLUTTER_RUN_STATUS=debug-session-started", source)
        self.assertIn("flutter build apk --debug", source)
        self.assertIn("flutter build ios --debug --no-codesign", source)

    def test_dry_run_prints_actions_without_requiring_network(self) -> None:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8") as password_file:
            password_file.write("not-a-real-password\n")
            password_file.flush()

            result = subprocess.run(
                [
                    "zsh",
                    str(SCRIPT_PATH),
                    "--dry-run",
                    "--password-file",
                    password_file.name,
                    "--remote-dir",
                    "/tmp/hydracamv2",
                    "jose@example.invalid",
                ],
                check=True,
                capture_output=True,
                text=True,
                env={**os.environ, "LC_ALL": "C"},
            )

        self.assertIn("DRY RUN", result.stdout)
        self.assertIn("rsync", result.stdout)
        self.assertIn("jose@example.invalid:/tmp/hydracamv2/", result.stdout)
        self.assertIn("prepare_macos_dev_host.zsh", result.stdout)
        self.assertIn("--skip-validation", result.stdout)
        self.assertNotIn("not-a-real-password", result.stdout)


if __name__ == "__main__":
    unittest.main()
