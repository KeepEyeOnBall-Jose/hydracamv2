#!/usr/bin/env python3
"""Regression tests for store-readiness lane scoping."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_SOURCE = REPO_ROOT / "scripts" / "check_store_readiness.sh"


class StoreReadinessModeScopeTest(unittest.TestCase):
    def test_upload_ios_does_not_emit_android_only_failures(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self._create_fixture(Path(temp_dir))

            result = self._run_readiness(root, "upload-ios")

            self.assertNotIn("Android manifest", result.output)
            self.assertNotIn("Android app build.gradle", result.output)
            self.assertNotIn("Android upload certificate", result.output)
            self.assertNotIn("Android fastlane", result.output)
            self.assertNotIn("Android key.properties", result.output)
            self.assertNotIn("Android launcher icon", result.output)
            self.assertNotIn("Android AAB", result.output)
            self.assertNotIn("GOOGLE_PLAY_JSON_KEY", result.output)

    def test_upload_android_does_not_emit_ios_only_failures(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = self._create_fixture(Path(temp_dir))

            result = self._run_readiness(root, "upload-android")

            self.assertNotIn("iOS Info.plist", result.output)
            self.assertNotIn("iOS privacy manifest", result.output)
            self.assertNotIn("iOS Xcode project", result.output)
            self.assertNotIn("iOS fastlane", result.output)
            self.assertNotIn("iOS app icon", result.output)
            self.assertNotIn("iOS IPA", result.output)
            self.assertNotIn("App Store Connect", result.output)

    def _create_fixture(self, root: Path) -> Path:
        scripts_dir = root / "scripts"
        scripts_dir.mkdir(parents=True)
        shutil.copy2(SCRIPT_SOURCE, scripts_dir / "check_store_readiness.sh")

        (root / "credentials").mkdir()
        (root / "credentials" / "AuthKey_TEST.p8").write_text(
            "fixture app store key\n",
            encoding="utf-8",
        )
        (root / "credentials" / "google-play.json").write_text(
            "{}\n",
            encoding="utf-8",
        )

        bin_dir = root / "bin"
        bin_dir.mkdir()
        self._write_executable(
            bin_dir / "plutil",
            """#!/usr/bin/env bash
case "$1" in
  -lint)
    exit 0
    ;;
  -extract)
    printf 'false\n'
    exit 0
    ;;
esac
exit 0
""",
        )
        self._write_executable(
            bin_dir / "file",
            """#!/usr/bin/env bash
printf '%s: PNG image data\\n' "$1"
""",
        )
        for command in ("keytool", "unzip", "zip"):
            self._write_executable(
                bin_dir / command,
                """#!/usr/bin/env bash
exit 0
""",
            )

        return root

    def _run_readiness(self, root: Path, mode: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{root / 'bin'}:{env['PATH']}",
                "APP_STORE_CONNECT_API_KEY_PATH": str(
                    root / "credentials" / "AuthKey_TEST.p8"
                ),
                "GOOGLE_PLAY_JSON_KEY": str(root / "credentials" / "google-play.json"),
                "HYDRACAM_PRIVACY_POLICY_URL": "https://store.hydracam.app/privacy",
                "HYDRACAM_SUPPORT_URL": "https://store.hydracam.app/support",
                "HYDRACAM_ACCOUNT_DELETION_URL": (
                    "https://store.hydracam.app/account-deletion"
                ),
            }
        )
        result = subprocess.run(
            ["bash", str(root / "scripts" / "check_store_readiness.sh"), mode],
            cwd=root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        result.output = result.stdout
        return result

    def _write_executable(self, path: Path, body: str) -> None:
        path.write_text(textwrap.dedent(body).lstrip(), encoding="utf-8")
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
