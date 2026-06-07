#!/usr/bin/env python3
"""Tests for the Android screen brightness helper."""

from __future__ import annotations

import importlib.util
import io
import unittest
from contextlib import redirect_stdout
from pathlib import Path

SCRIPT_PATH = Path(__file__).with_name("android_screen_brightness.py")


def load_module():
    spec = importlib.util.spec_from_file_location(
        "android_screen_brightness",
        SCRIPT_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load android_screen_brightness.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeRunner:
    def __init__(self) -> None:
        self.commands: list[list[str]] = []

    def __call__(self, command: list[str], *, timeout: int):
        self.commands.append(command)
        module = load_module()
        if command == ["adb", "devices", "-l"]:
            return module.CommandResult(
                returncode=0,
                stdout=(
                    "List of devices attached\n"
                    "RF8M90QE7LX device product:beyond0 model:SM_G970F\n"
                    "9d94c365 offline product:PB2 model:PB2_690M\n"
                    "192.168.178.64:5555 device product:hero2lte model:SM_G935F\n"
                ),
                stderr="",
            )
        if command[-3:] == ["get", "system", "screen_brightness"]:
            return module.CommandResult(returncode=0, stdout="180\n", stderr="")
        if command[-3:] == [
            "get",
            "system",
            "screen_brightness_mode",
        ]:
            return module.CommandResult(returncode=0, stdout="0\n", stderr="")
        return module.CommandResult(returncode=0, stdout="", stderr="")


class AndroidScreenBrightnessTests(unittest.TestCase):
    def test_list_devices_ignores_offline_and_unauthorized_rows(self) -> None:
        module = load_module()
        runner = FakeRunner()

        devices = module.list_devices("adb", timeout=15, runner=runner)

        self.assertEqual(
            [device.serial for device in devices],
            ["RF8M90QE7LX", "192.168.178.64:5555"],
        )

    def test_brightness_commands_disable_adaptive_brightness_first(self) -> None:
        module = load_module()

        commands = module.brightness_commands("RF8M90QE7LX", 1)

        self.assertEqual(
            commands,
            [
                [
                    "adb",
                    "-s",
                    "RF8M90QE7LX",
                    "shell",
                    "settings",
                    "put",
                    "system",
                    "screen_brightness_mode",
                    "0",
                ],
                [
                    "adb",
                    "-s",
                    "RF8M90QE7LX",
                    "shell",
                    "settings",
                    "put",
                    "system",
                    "screen_brightness",
                    "1",
                ],
            ],
        )

    def test_dim_runs_against_selected_devices_only(self) -> None:
        module = load_module()
        runner = FakeRunner()

        stdout = io.StringIO()
        with redirect_stdout(stdout):
            exit_code = module.main(
                [
                    "dim",
                    "--adb",
                    "adb",
                    "--device",
                    "RF8M90QE7LX",
                    "--timeout",
                    "15",
                ],
                runner=runner,
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(
            runner.commands,
            [
                ["adb", "devices", "-l"],
                [
                    "adb",
                    "-s",
                    "RF8M90QE7LX",
                    "shell",
                    "settings",
                    "put",
                    "system",
                    "screen_brightness_mode",
                    "0",
                ],
                [
                    "adb",
                    "-s",
                    "RF8M90QE7LX",
                    "shell",
                    "settings",
                    "put",
                    "system",
                    "screen_brightness",
                    "0",
                ],
            ],
        )

    def test_status_reads_brightness_and_mode(self) -> None:
        module = load_module()
        runner = FakeRunner()

        states = module.status_devices(
            "adb",
            [module.AndroidDevice("RF8M90QE7LX", "model:SM_G970F")],
            timeout=15,
            runner=runner,
        )

        self.assertEqual(states[0].brightness, "180")
        self.assertEqual(states[0].mode, "0")
        self.assertEqual(
            runner.commands,
            [
                [
                    "adb",
                    "-s",
                    "RF8M90QE7LX",
                    "shell",
                    "settings",
                    "get",
                    "system",
                    "screen_brightness",
                ],
                [
                    "adb",
                    "-s",
                    "RF8M90QE7LX",
                    "shell",
                    "settings",
                    "get",
                    "system",
                    "screen_brightness_mode",
                ],
            ],
        )


if __name__ == "__main__":
    unittest.main()
