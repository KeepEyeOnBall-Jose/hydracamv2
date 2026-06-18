#!/usr/bin/env python3
"""Tests for the Android hardware UI e2e runner."""

from __future__ import annotations

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


if __name__ == "__main__":
    unittest.main()
