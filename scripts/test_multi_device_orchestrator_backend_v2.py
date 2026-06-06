#!/usr/bin/env python3
"""Focused regression tests for manifest-backed backend verification."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.multi_device_orchestrator import DeviceTarget, MultiDeviceOrchestrator


class MultiDeviceOrchestratorBackendTests(unittest.TestCase):
    def _make_orchestrator(self) -> MultiDeviceOrchestrator:
        temp_root = Path(tempfile.mkdtemp(prefix="hydracam_orchestrator_test_"))
        devices = [
            DeviceTarget(
                serial="emulator-5554",
                role="master",
                local_port=5900,
                name="master-0",
            )
        ]
        orchestrator = MultiDeviceOrchestrator(
            devices,
            scenario="quad_smoke_extended",
            output_root=temp_root,
            backend_base_url=None,
            backend_token=None,
        )
        orchestrator._prepare_run_directory()
        return orchestrator

    def test_extract_session_guid_from_nested_command_response(self) -> None:
        orchestrator = self._make_orchestrator()
        response = {
            "status": "ok",
            "command": "start_session",
            "result": {"sessionGuid": "nested-guid-123"},
        }
        self.assertEqual(
            orchestrator._extract_session_guid_from_command_response(response),
            "nested-guid-123",
        )

    def test_manifest_start_session_stores_nested_guid_in_context(self) -> None:
        orchestrator = self._make_orchestrator()
        orchestrator._post_with_retry = lambda *_args, **_kwargs: {
            "status": "ok",
            "command": "start_session",
            "result": {"sessionGuid": "context-guid-456"},
        }
        result = orchestrator._manifest_step_command(
            {
                "action": "command",
                "command": "start_session",
                "payload": {},
            }
        )
        self.assertEqual(result["command"], "start_session")
        self.assertEqual(orchestrator.context.get("sessionGuid"), "context-guid-456")

    def test_backend_verification_uses_context_guid_fallback(self) -> None:
        orchestrator = self._make_orchestrator()
        orchestrator.context["sessionGuid"] = "fallback-guid-789"
        orchestrator.backend_base_url = "https://example.invalid"
        orchestrator.backend_token = "token"
        orchestrator._fetch_backend_session = lambda session_guid: {
            "guid": session_guid,
            "assets": [],
        }
        orchestrator._download_backend_asset = lambda *_args, **_kwargs: {
            "url": "https://example.invalid/asset",
            "file": "unused",
            "bytes": 0,
            "sha256": "0",
        }
        report = orchestrator._run_backend_verification({"sessionGuid": None})
        self.assertIsNotNone(report)
        assert report is not None
        self.assertEqual(report["sessionGuid"], "fallback-guid-789")
        self.assertEqual(report["assetCount"], 0)


if __name__ == "__main__":
    unittest.main()
