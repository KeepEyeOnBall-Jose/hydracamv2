#!/usr/bin/env python3
"""Regression tests for wearable replay readiness checks."""

from __future__ import annotations

import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_wearable_replay_readiness as readiness


REPO_ROOT = Path(__file__).resolve().parents[1]


class WearableReplayReadinessTest(unittest.TestCase):
    def test_mock_mode_passes_current_repo_contract(self) -> None:
        results = readiness.run_checks(
            root=REPO_ROOT,
            mode="mock",
            env={},
            check_network=False,
            timeout_seconds=0.1,
        )

        failures = [result for result in results if not result.ok]

        self.assertEqual([], failures)
        self.assertGreaterEqual(len(results), 45)

    def test_dat_mode_passes_repo_controlled_dependency_boundary(self) -> None:
        results = readiness.run_checks(
            root=REPO_ROOT,
            mode="dat",
            env={},
            check_network=False,
            timeout_seconds=0.1,
        )

        failures = [result for result in results if not result.ok]
        android_boundary = [
            result
            for result in results
            if result.label
            == "Default Android build keeps private Meta DAT SDK artifacts gated"
        ]

        self.assertEqual([], failures)
        self.assertEqual(1, len(android_boundary))
        self.assertTrue(android_boundary[0].ok)

    def test_dat_network_check_reports_missing_package_token(self) -> None:
        results = readiness.run_checks(
            root=REPO_ROOT,
            mode="dat",
            env={},
            check_network=True,
            timeout_seconds=0.1,
        )

        package_access = [
            result
            for result in results
            if result.label == "Android DAT GitHub Package access"
        ]

        self.assertEqual(1, len(package_access))
        self.assertFalse(package_access[0].ok)
        self.assertIn("GITHUB_TOKEN", package_access[0].detail)


if __name__ == "__main__":
    unittest.main()
