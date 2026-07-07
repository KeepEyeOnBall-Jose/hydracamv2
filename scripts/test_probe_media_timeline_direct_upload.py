#!/usr/bin/env python3
"""Tests for the media-timeline direct object upload probe."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import probe_media_timeline_direct_upload as probe


class MediaTimelineDirectUploadProbeTest(unittest.TestCase):
    def test_probe_runs_full_direct_upload_sequence(self) -> None:
        calls: list[tuple[str, str, object, bytes | None, dict[str, str]]] = []

        def fake_request(
            method: str,
            url: str,
            *,
            json_body: object | None = None,
            bytes_body: bytes | None = None,
            headers: dict[str, str] | None = None,
            timeout_seconds: float,
        ) -> object:
            del timeout_seconds
            calls.append((method, url, json_body, bytes_body, headers or {}))
            if url == "http://media.test/api/hydracam-bridge/compat/sessions/create":
                return {
                    "guid": "session-guid-1",
                    "sessionId": "probe-session",
                    "uploadToken": "upload-token-1",
                }
            if url == "http://media.test/api/hydracam-bridge/sessions/session-guid-1/uploads/start":
                self.assertEqual("Bearer upload-token-1", (headers or {})["Authorization"])
                return {
                    "eventId": "hydracam-session-guid-1",
                    "sessionGuid": "session-guid-1",
                    "objectKey": "events/hydracam-session-guid-1/probe.jpg",
                    "preferredStorage": "object-storage",
                    "mediaStorage": {
                        "startPath": "/api/media-storage/multipart/start",
                        "uploadPartPath": "/api/media-storage/multipart/upload-part",
                        "completeObjectPath": "/api/media-storage/multipart/complete",
                        "completeBridgePath": "/api/hydracam-bridge/sessions/session-guid-1/uploads/complete",
                    },
                }
            if url == "http://media.test/api/media-storage/multipart/start":
                return {
                    "key": "events/hydracam-session-guid-1/probe.jpg",
                    "uploadId": "upload-1",
                    "locator": "s3://media/events/hydracam-session-guid-1/probe.jpg",
                }
            if url == (
                "http://media.test/api/media-storage/multipart/upload-part?"
                "key=events%2Fhydracam-session-guid-1%2Fprobe.jpg&"
                "uploadId=upload-1&partNumber=1"
            ):
                self.assertEqual(b"image-bytes", bytes_body)
                return {
                    "ETag": '"part-one"',
                    "PartNumber": 1,
                }
            if url == "http://media.test/api/media-storage/multipart/complete":
                return {
                    "locator": "s3://media/events/hydracam-session-guid-1/probe.jpg",
                    "registered": {
                        "fileId": "file-1",
                        "videoId": "file-1",
                        "created": True,
                    },
                }
            if url == "http://media.test/api/hydracam-bridge/sessions/session-guid-1/uploads/complete":
                self.assertEqual("Bearer upload-token-1", (headers or {})["Authorization"])
                return {
                    "eventId": "hydracam-session-guid-1",
                    "fileId": "file-1",
                    "created": True,
                }
            if url == "http://media.test/api/hydracam-bridge/sessions/session-guid-1/status":
                return {
                    "eventId": "hydracam-session-guid-1",
                    "sessionGuid": "session-guid-1",
                    "mediaCount": 1,
                }
            raise AssertionError(f"unexpected request {method} {url}")

        report = probe.build_probe_report(
            "http://media.test/api",
            filename="probe.jpg",
            media_bytes=b"image-bytes",
            mime_type="image/jpeg",
            kind="photo",
            device_id="device-a",
            request_json=fake_request,
            timeout_seconds=0.1,
        )

        self.assertTrue(report["ok"])
        self.assertEqual("session-guid-1", report["sessionGuid"])
        self.assertEqual("hydracam-session-guid-1", report["eventId"])
        self.assertEqual("file-1", report["fileId"])
        self.assertNotIn("upload-token-1", probe.json.dumps(report))
        self.assertEqual(
            "[redacted]",
            report["steps"][0]["payload"]["uploadToken"],
        )
        self.assertEqual(
            [
                "POST",
                "POST",
                "POST",
                "PUT",
                "POST",
                "POST",
                "GET",
            ],
            [method for method, *_rest in calls],
        )

    def test_write_report_creates_json_and_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            paths = probe.write_report(
                Path(tmp),
                {
                    "ok": True,
                    "eventId": "event-1",
                    "sessionGuid": "session-1",
                    "fileId": "file-1",
                    "locator": "s3://media/events/event-1/probe.jpg",
                    "steps": [{"name": "completeBridgeUpload", "status": "ok"}],
                },
            )

            self.assertTrue(paths["json"].exists())
            self.assertTrue(paths["markdown"].exists())
            self.assertIn(
                "media-timeline direct upload probe: PASS",
                paths["markdown"].read_text(),
            )


if __name__ == "__main__":
    unittest.main()
