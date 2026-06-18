import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_android_always_on_lab_soak as soak


class AndroidAlwaysOnLabSoakTest(unittest.TestCase):
    def test_assess_soak_passes_ready_s10e_on_power_with_bridge_health(self):
        summary = {
            "sampleCount": 3,
            "devices": {
                "RF8M90QE7LX": {
                    "samples": 3,
                    "latestPids": [12345],
                    "latestBattery": {
                        "level": 88,
                        "usb_powered": True,
                        "temperature": 334,
                    },
                    "temperatureTenthsCMax": 351,
                },
            },
        }
        identities = {
            "RF8M90QE7LX": {
                "model": "SM-G970F",
                "android_release": "12",
                "android_sdk": "31",
            },
        }
        bridge_checks = [
            {
                "url": "http://192.168.178.42:4762/healthz",
                "ok": True,
                "status": 200,
                "json": {"automationTargetId": "RF8M90QE7LX"},
            }
        ]

        assessment = soak.assess_soak(
            summary,
            identities,
            min_samples=3,
            expected_model="SM-G970F",
            require_app_process=True,
            bridge_checks=bridge_checks,
            expected_bridge_target_ids=["RF8M90QE7LX"],
        )

        self.assertEqual(assessment["status"], "passed")
        self.assertEqual(assessment["failures"], [])
        self.assertEqual(assessment["deviceCount"], 1)

    def test_assess_soak_fails_when_app_process_is_missing_or_model_is_wrong(self):
        summary = {
            "sampleCount": 2,
            "devices": {
                "android-01": {
                    "samples": 2,
                    "latestPids": [],
                    "latestBattery": {
                        "level": 58,
                        "usb_powered": True,
                    },
                },
            },
        }
        identities = {
            "android-01": {
                "model": "SM-G960F",
                "android_release": "10",
                "android_sdk": "29",
            },
        }

        assessment = soak.assess_soak(
            summary,
            identities,
            min_samples=3,
            expected_model="SM-G970F",
            require_app_process=True,
            bridge_checks=[],
        )

        self.assertEqual(assessment["status"], "failed")
        self.assertIn("android-01:samples-below-minimum", assessment["failures"])
        self.assertIn("android-01:unexpected-model:SM-G960F", assessment["failures"])
        self.assertIn("android-01:app-process-missing", assessment["failures"])

    def test_assess_soak_fails_when_bridge_identity_is_not_selected_device(self):
        summary = {
            "sampleCount": 3,
            "devices": {
                "RF8M90QE7LX": {
                    "samples": 3,
                    "latestPids": [12345],
                    "latestBattery": {
                        "level": 88,
                        "usb_powered": True,
                        "temperature": 334,
                    },
                    "temperatureTenthsCMax": 351,
                },
            },
        }
        identities = {
            "RF8M90QE7LX": {
                "model": "SM-G970F",
                "android_release": "12",
                "android_sdk": "31",
            },
        }
        bridge_checks = [
            {
                "url": "http://192.168.178.99:4762/healthz",
                "ok": True,
                "status": 200,
                "json": {"automationTargetId": "STALE-S10E"},
            }
        ]

        assessment = soak.assess_soak(
            summary,
            identities,
            min_samples=3,
            expected_model="SM-G970F",
            require_app_process=True,
            bridge_checks=bridge_checks,
            expected_bridge_target_ids=["RF8M90QE7LX"],
        )

        self.assertEqual(assessment["status"], "failed")
        self.assertIn(
            "bridge-healthz-unexpected-target:0:STALE-S10E",
            assessment["failures"],
        )

    def test_write_evidence_files_creates_durable_summary_and_raw_samples(self):
        metadata = {
            "runId": "20260615-android-always-on-lab-soak",
            "package": "com.amaia23.hydracam",
        }
        samples = [
            {"serial": "RF8M90QE7LX", "elapsed_seconds": 0},
            {"serial": "RF8M90QE7LX", "elapsed_seconds": 60},
        ]
        summary = {"sampleCount": 2, "devices": {"RF8M90QE7LX": {"samples": 2}}}
        assessment = {"status": "passed", "failures": [], "warnings": []}
        bridge_checks = [{"url": "http://example.test/healthz", "ok": True}]

        with tempfile.TemporaryDirectory() as tempdir:
            run_dir = Path(tempdir) / "soak"
            soak.write_evidence_files(
                run_dir,
                metadata=metadata,
                samples=samples,
                power_summary=summary,
                assessment=assessment,
                bridge_checks=bridge_checks,
            )

            always_on_summary = json.loads(
                (run_dir / "always-on-summary.json").read_text(
                    encoding="utf-8",
                )
            )
            raw_samples = (run_dir / "raw-samples.jsonl").read_text(
                encoding="utf-8",
            )

            self.assertEqual(always_on_summary["status"], "passed")
            self.assertTrue((run_dir / "power-summary.json").exists())
            self.assertTrue((run_dir / "bridge-healthz.json").exists())
            self.assertEqual(len(raw_samples.strip().splitlines()), 2)


if __name__ == "__main__":
    unittest.main()
