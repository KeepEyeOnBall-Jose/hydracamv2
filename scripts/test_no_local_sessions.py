import pathlib
import re
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]

RUNTIME_FILES = [
    pathlib.Path("lib/master/master_screen.dart"),
    pathlib.Path("scripts/ios_capture_repro.py"),
    pathlib.Path("scripts/run_parallel_device_matrix.py"),
    pathlib.Path("scripts/run_rotating_master_slave_matrix.py"),
]

CAPTURE_SCRIPT_FILES = [
    pathlib.Path("scripts/ios_capture_repro.py"),
    pathlib.Path("scripts/run_parallel_device_matrix.py"),
    pathlib.Path("scripts/run_rotating_master_slave_matrix.py"),
]

FORBIDDEN_LITERALS = [
    "start_local_session",
    "automation-local",
]

FORBIDDEN_CAPTURE_SCRIPT_LITERALS = [
    "localOnly",
]

FORBIDDEN_LOCAL_GUID_PATTERNS = [
    re.compile(r"[\"']local-\$"),
    re.compile(r"[\"']local-[A-Za-z0-9_{}-]*(session|guid)", re.IGNORECASE),
]

FORBIDDEN_LOCAL_ONLY_OBFUSCATION_PATTERNS = [
    re.compile(r"[\"']local[\"']\s+[\"']Only[\"']"),
]


class NoLocalRuntimeSessionTests(unittest.TestCase):
    def test_runtime_automation_paths_do_not_expose_local_sessions(self):
        for relative_path in RUNTIME_FILES:
            with self.subTest(path=str(relative_path)):
                text = (REPO_ROOT / relative_path).read_text()
                for literal in FORBIDDEN_LITERALS:
                    self.assertNotIn(literal, text)
                for pattern in FORBIDDEN_LOCAL_GUID_PATTERNS:
                    self.assertIsNone(pattern.search(text))
                for pattern in FORBIDDEN_LOCAL_ONLY_OBFUSCATION_PATTERNS:
                    self.assertIsNone(pattern.search(text))

    def test_capture_scripts_start_backend_sessions_and_do_not_disable_uploads(
        self,
    ):
        for relative_path in CAPTURE_SCRIPT_FILES:
            with self.subTest(path=str(relative_path)):
                text = (REPO_ROOT / relative_path).read_text()
                self.assertIn("start_session", text)
                for literal in FORBIDDEN_CAPTURE_SCRIPT_LITERALS:
                    self.assertNotIn(literal, text)
                self.assertNotIn('"autoUploadMaterials": False', text)
                self.assertNotIn("'autoUploadMaterials': False", text)

    def test_master_rejects_legacy_local_only_payload_explicitly(self):
        text = (REPO_ROOT / "lib/master/master_screen.dart").read_text()

        self.assertIn('"localOnly"', text)
        self.assertIn("backend sessions are mandatory", text)


if __name__ == "__main__":
    unittest.main()
