#!/usr/bin/env python3
"""Tests for wearable replay non-hardware proof helpers."""

from __future__ import annotations

import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_wearable_replay_non_hardware_proof as proof


class WearableReplayNonHardwareProofTest(unittest.TestCase):
    def test_extract_live_session_guid_uses_last_started_session(self) -> None:
        output = """
        Log registered: {message: Session started with GUID: old-session on device type: Master}
        Log registered: {message: Session started with GUID: wearable-live-123 on device type: Master}
        """

        self.assertEqual("wearable-live-123", proof.extract_live_session_guid(output))

    def test_extract_live_session_guid_rejects_missing_session(self) -> None:
        with self.assertRaises(proof.ProofFailure):
            proof.extract_live_session_guid("All tests passed")

    def test_wearable_replay_row_from_enriched_validates_sidecar_counts(self) -> None:
        row = proof.wearable_replay_row_from_enriched([
            {
                "videoId": "video-1",
                "wearableReplay": {
                    "replayAngle": True,
                    "captureMode": "rollingHighlight",
                    "syncConfidence": "green",
                    "sidecars": {
                        "trackCount": 2,
                        "sampleFileCount": 2,
                        "sampleCount": 3,
                        "calibrationCount": 1,
                        "markerCount": 1,
                        "feedbackCount": 2,
                    },
                },
            },
        ])

        self.assertEqual("video-1", row["videoId"])

    def test_wearable_replay_row_from_enriched_rejects_wrong_counts(self) -> None:
        with self.assertRaises(proof.ProofFailure):
            proof.wearable_replay_row_from_enriched([
                {
                    "videoId": "video-1",
                    "wearableReplay": {
                        "replayAngle": True,
                        "captureMode": "rollingHighlight",
                        "syncConfidence": "green",
                        "sidecars": {
                            "trackCount": 2,
                            "sampleFileCount": 2,
                            "sampleCount": 2,
                            "calibrationCount": 1,
                            "markerCount": 1,
                            "feedbackCount": 2,
                        },
                    },
                },
            ])

    def test_prefixed_event_id_candidate_is_used_for_wearable_sessions(self) -> None:
        candidates: list[str] = []

        def fake_fetch(url: str, *, timeout_seconds: float) -> object:
            candidates.append(url)
            if "/events/wearable-live-123/" in url:
                raise proof.ProofFailure("404")
            return [{"videoId": "video-1", "wearableReplay": {"replayAngle": True}}]

        original_fetch = proof.fetch_json
        proof.fetch_json = fake_fetch
        try:
            event_id, _ = proof.fetch_enriched_media_for_session(
                api_base_url="http://example.test/api",
                session_guid="wearable-live-123",
                timeout_seconds=0.1,
            )
        finally:
            proof.fetch_json = original_fetch

        self.assertEqual("hydracam-wearable-live-123", event_id)
        self.assertEqual(2, len(candidates))


if __name__ == "__main__":
    unittest.main()
