#!/usr/bin/env python3
"""Tests for media-timeline bridge preflight helpers."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import check_media_timeline_bridge as bridge_check


class MediaTimelineBridgePreflightTest(unittest.TestCase):
    def test_preflight_records_backend_storage_and_bridge_route(self) -> None:
        calls: list[tuple[str, str]] = []

        def fake_fetch(url: str, *, method: str = "GET", timeout_seconds: float) -> object:
            calls.append((method, url))
            if url == "http://media.test/health?deep=1":
                return {"service": "backend", "status": "ok"}
            if url == "http://media.test/api/media-storage/status":
                return {
                    "enabled": True,
                    "provider": "s3",
                    "bucket": "media-bucket",
                    "signedUrlTtlSeconds": 300,
                }
            if (
                method == "POST"
                and url
                == "http://media.test/api/hydracam-bridge/sessions/00000000-0000-4000-8000-000000000000/uploads/start"
            ):
                raise bridge_check.HttpStatusError(
                    status=401,
                    payload={"error": "Missing or malformed Authorization header"},
                )
            raise AssertionError(f"unexpected request {method} {url}")

        report = bridge_check.build_preflight_report(
            "http://media.test/api",
            fetch_json=fake_fetch,
            timeout_seconds=0.1,
        )

        self.assertTrue(report["ok"])
        self.assertEqual("http://media.test/api", report["apiBaseUrl"])
        self.assertEqual("ok", report["checks"]["backendHealth"]["status"])
        self.assertEqual("ok", report["checks"]["mediaStorage"]["status"])
        self.assertEqual("s3", report["checks"]["mediaStorage"]["provider"])
        self.assertEqual("ok", report["checks"]["directUploadRoute"]["status"])
        self.assertEqual(401, report["checks"]["directUploadRoute"]["httpStatus"])
        self.assertEqual(
            [
                ("GET", "http://media.test/health?deep=1"),
                ("GET", "http://media.test/api/media-storage/status"),
                (
                    "POST",
                    "http://media.test/api/hydracam-bridge/sessions/00000000-0000-4000-8000-000000000000/uploads/start",
                ),
            ],
            calls,
        )

    def test_preflight_fails_when_object_storage_is_disabled(self) -> None:
        def fake_fetch(url: str, *, method: str = "GET", timeout_seconds: float) -> object:
            if url.endswith("/health?deep=1"):
                return {"service": "backend"}
            if url.endswith("/media-storage/status"):
                return {
                    "enabled": False,
                    "provider": "s3",
                    "bucket": None,
                    "signedUrlTtlSeconds": 300,
                }
            if method == "POST":
                raise bridge_check.HttpStatusError(
                    status=401,
                    payload={"error": "Missing or malformed Authorization header"},
                )
            raise AssertionError(f"unexpected request {method} {url}")

        report = bridge_check.build_preflight_report(
            "http://media.test/api",
            fetch_json=fake_fetch,
            timeout_seconds=0.1,
        )

        self.assertFalse(report["ok"])
        self.assertEqual("blocked", report["checks"]["mediaStorage"]["status"])
        self.assertIn("object storage disabled", report["checks"]["mediaStorage"]["message"])

    def test_write_report_creates_json_and_markdown_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            report = {
                "ok": True,
                "apiBaseUrl": "http://media.test/api",
                "checks": {
                    "backendHealth": {"status": "ok"},
                    "mediaStorage": {"status": "ok", "provider": "s3"},
                    "directUploadRoute": {"status": "ok", "httpStatus": 401},
                },
            }

            paths = bridge_check.write_report(run_dir, report)

            self.assertTrue(paths["json"].exists())
            self.assertTrue(paths["markdown"].exists())
            self.assertIn("media-timeline bridge preflight: PASS", paths["markdown"].read_text())


if __name__ == "__main__":
    unittest.main()
