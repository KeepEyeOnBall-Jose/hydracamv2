#!/usr/bin/env python3
"""Tests for the HydraCam evidence pack helper."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


class EvidencePackCliTests(unittest.TestCase):
    def run_cli(self, *args: str, root: Path) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["HYDRACAM_EVIDENCE_ROOT"] = str(root)
        return subprocess.run(
            [sys.executable, "scripts/evidence_pack.py", *args],
            cwd=REPO_ROOT,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )

    def test_start_run_finalize_and_check_tier_d_pack(self) -> None:
        with tempfile.TemporaryDirectory(prefix="hydracam_evidence_pack_") as tmp:
            root = Path(tmp)
            start = self.run_cli(
                "start",
                "--item",
                "Pure service evidence test",
                "--slug",
                "service-evidence-test",
                "--source",
                "unit-test",
                "--tier",
                "D",
                "--acceptance",
                "The helper records command output",
                root=root,
            )
            self.assertEqual(start.returncode, 0, start.stderr)
            run_dir = Path(start.stdout.strip())

            run = self.run_cli(
                "run",
                str(run_dir),
                "--",
                sys.executable,
                "-c",
                "print('evidence command ran')",
                root=root,
            )
            self.assertEqual(run.returncode, 0, run.stderr)

            finalize = self.run_cli(
                "finalize",
                str(run_dir),
                "--status",
                "passed",
                "--note",
                "Unit-test pack validates Tier D behavior.",
                root=root,
            )
            self.assertEqual(finalize.returncode, 0, finalize.stderr)

            check = self.run_cli("check", str(run_dir), root=root)
            self.assertEqual(check.returncode, 0, check.stderr)
            self.assertIn("Evidence pack valid", check.stdout)

    def test_tier_b_requires_hardware_artifact_directories(self) -> None:
        with tempfile.TemporaryDirectory(prefix="hydracam_evidence_pack_") as tmp:
            root = Path(tmp)
            start = self.run_cli(
                "start",
                "--item",
                "UI evidence test",
                "--slug",
                "ui-evidence-test",
                "--source",
                "unit-test",
                "--tier",
                "B",
                "--acceptance",
                "The app screen is visible",
                root=root,
            )
            self.assertEqual(start.returncode, 0, start.stderr)
            run_dir = Path(start.stdout.strip())

            run = self.run_cli(
                "run",
                str(run_dir),
                "--",
                sys.executable,
                "-c",
                "print('no hardware artifacts yet')",
                root=root,
            )
            self.assertEqual(run.returncode, 0, run.stderr)

            finalize = self.run_cli(
                "finalize",
                str(run_dir),
                "--status",
                "passed",
                root=root,
            )
            self.assertEqual(finalize.returncode, 0, finalize.stderr)

            check = self.run_cli("check", str(run_dir), root=root)
            self.assertNotEqual(check.returncode, 0)
            self.assertIn("declare at least one device", check.stderr)
            self.assertIn("screenshots/", check.stderr)
            self.assertIn("video/", check.stderr)
            self.assertIn("device-logs/", check.stderr)


if __name__ == "__main__":
    unittest.main()
