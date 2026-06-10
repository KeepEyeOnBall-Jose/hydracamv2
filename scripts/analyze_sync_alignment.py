#!/usr/bin/env python3
"""Analyze cross-device clock-sync alignment from two media `.sync.json` sidecars.

This is the ground-truth verification tool for the clock-sync feature. Given two
media sidecars (one per device) plus the observed media-relative time of a single
synchronized visual event (camera flash / clap board) in each clip, it computes
how far apart the two devices placed that same real-world event on the shared
(master) clock, and reports PASS/FAIL against the <50 ms NTP alignment target.

Sync model (see lib/services/session_manager.dart and lib/models/sync_metadata.dart):
  - Each sidecar carries the recording window in device wall-clock UTC
    (`startRecordingDate`/`endRecordingDate` for video, `captureDate` for photo)
    and a `sync` block with `offsetMs`, `uncertaintyMs`, and `confidence`.
  - `offsetMs` is (master_clock - local_clock); so
        sharedClockTime = localTime + offsetMs.
  - For an event seen `eventSeconds` into a clip, its device wall-clock time is
        startDate + eventSeconds,
    and its shared-clock time is
        startDate + eventSeconds + offsetMs.
  - The cross-device alignment error is the difference of the two clips'
    shared-clock event times. Zero means perfect alignment.

Uncertainty combination: we use the root-sum-square (RSS),
    combined = sqrt(uA^2 + uB^2).
RSS is used (rather than the linear sum uA + uB) because the two devices'
calibration uncertainties are independent error estimates; RSS is the standard
way to propagate independent uncertainties and is the less pessimistic, more
physically representative bound. The pass criterion is intentionally
conservative regardless:
    |alignment error| + combined uncertainty < 50 ms.

Standard library only; no third-party dependencies.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Cross-device alignment target from the NTP sync specification.
ALIGNMENT_THRESHOLD_MS = 50.0


class SyncDataError(Exception):
    """Raised when a sidecar file is missing, unreadable, or malformed."""


def _parse_iso8601_utc(value: str) -> datetime:
    """Parse an ISO-8601 timestamp into an aware UTC datetime.

    Accepts a trailing 'Z' (Dart's `toIso8601String()` for UTC emits 'Z') as
    well as explicit offsets. Naive timestamps are assumed to be UTC, matching
    the app contract that these dates are written in UTC.
    """
    if not isinstance(value, str) or not value.strip():
        raise SyncDataError(f"Expected an ISO-8601 timestamp string, got: {value!r}")
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError as exc:
        raise SyncDataError(f"Could not parse ISO-8601 timestamp {value!r}: {exc}") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _require(mapping: dict[str, Any], key: str, context: str) -> Any:
    if key not in mapping:
        raise SyncDataError(f"Missing required field '{key}' in {context}")
    return mapping[key]


def _as_number(value: Any, key: str, context: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise SyncDataError(
            f"Field '{key}' in {context} must be a number, got: {value!r}"
        )
    return float(value)


def load_sidecar(path: str) -> dict[str, Any]:
    """Load and minimally validate a `.sync.json` sidecar from disk."""
    file_path = Path(path)
    if not file_path.exists():
        raise SyncDataError(f"Sidecar file not found: {path}")
    try:
        raw = file_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SyncDataError(f"Could not read sidecar {path}: {exc}") from exc
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SyncDataError(f"Sidecar {path} is not valid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SyncDataError(f"Sidecar {path} must be a JSON object")
    return data


def extract_clip(data: dict[str, Any], context: str) -> dict[str, Any]:
    """Pull the fields this tool needs from a parsed sidecar dict.

    Returns a normalized dict: start (datetime), offset_ms, uncertainty_ms,
    confidence, device_id, media_path, date_field (which timestamp was used).
    Works for both video sidecars (`startRecordingDate`) and photo sidecars
    (`captureDate`).
    """
    if "startRecordingDate" in data:
        date_field = "startRecordingDate"
    elif "captureDate" in data:
        date_field = "captureDate"
    else:
        raise SyncDataError(
            f"{context} has neither 'startRecordingDate' (video) nor "
            "'captureDate' (photo)"
        )
    start = _parse_iso8601_utc(data[date_field])

    sync = _require(data, "sync", context)
    if not isinstance(sync, dict):
        raise SyncDataError(f"Field 'sync' in {context} must be an object")
    sync_context = f"{context} -> sync"
    offset_ms = _as_number(_require(sync, "offsetMs", sync_context), "offsetMs", sync_context)
    uncertainty_ms = _as_number(
        _require(sync, "uncertaintyMs", sync_context), "uncertaintyMs", sync_context
    )
    confidence = _require(sync, "confidence", sync_context)
    if confidence not in ("green", "yellow", "red"):
        raise SyncDataError(
            f"Field 'sync.confidence' in {context} must be green|yellow|red, "
            f"got: {confidence!r}"
        )

    return {
        "start": start,
        "date_field": date_field,
        "offset_ms": offset_ms,
        "uncertainty_ms": uncertainty_ms,
        "confidence": confidence,
        "device_id": data.get("deviceId"),
        "media_path": data.get("mediaPath"),
    }


def shared_clock_event_ms(clip: dict[str, Any], event_seconds: float) -> float:
    """Shared-clock time of the event, in milliseconds since the Unix epoch.

    sharedClockTime = startDate + eventSeconds + offsetMs
    """
    start_ms = clip["start"].timestamp() * 1000.0
    return start_ms + event_seconds * 1000.0 + clip["offset_ms"]


def analyze(
    clip_a: dict[str, Any],
    event_a_seconds: float,
    clip_b: dict[str, Any],
    event_b_seconds: float,
) -> dict[str, Any]:
    """Compute alignment error, combined uncertainty, and PASS/FAIL."""
    shared_a = shared_clock_event_ms(clip_a, event_a_seconds)
    shared_b = shared_clock_event_ms(clip_b, event_b_seconds)
    # Signed error: positive means clip A placed the event later on the shared
    # clock than clip B.
    error_ms = shared_a - shared_b
    combined_uncertainty_ms = math.sqrt(
        clip_a["uncertainty_ms"] ** 2 + clip_b["uncertainty_ms"] ** 2
    )
    margin_ms = abs(error_ms) + combined_uncertainty_ms
    passed = margin_ms < ALIGNMENT_THRESHOLD_MS
    return {
        "shared_a_ms": shared_a,
        "shared_b_ms": shared_b,
        "error_ms": error_ms,
        "combined_uncertainty_ms": combined_uncertainty_ms,
        "margin_ms": margin_ms,
        "passed": passed,
    }


def _ms_to_iso(ms: float) -> str:
    return datetime.fromtimestamp(ms / 1000.0, tz=timezone.utc).isoformat()


def render_report(
    clip_a: dict[str, Any],
    event_a_seconds: float,
    clip_b: dict[str, Any],
    event_b_seconds: float,
    result: dict[str, Any],
) -> str:
    lines: list[str] = []
    lines.append("HydraCam clock-sync ground-truth alignment analysis")
    lines.append("=" * 52)
    lines.append("")
    lines.append("Clip A:")
    lines.append(f"  media:            {clip_a.get('media_path')}")
    lines.append(f"  deviceId:         {clip_a.get('device_id')}")
    lines.append(f"  {clip_a['date_field']}: {clip_a['start'].isoformat()}")
    lines.append(f"  event offset (s): {event_a_seconds}")
    lines.append(f"  offsetMs:         {clip_a['offset_ms']:.3f}")
    lines.append(f"  uncertaintyMs:    {clip_a['uncertainty_ms']:.3f}")
    lines.append(f"  confidence:       {clip_a['confidence']}")
    lines.append(f"  shared-clock event time: {_ms_to_iso(result['shared_a_ms'])}")
    lines.append("")
    lines.append("Clip B:")
    lines.append(f"  media:            {clip_b.get('media_path')}")
    lines.append(f"  deviceId:         {clip_b.get('device_id')}")
    lines.append(f"  {clip_b['date_field']}: {clip_b['start'].isoformat()}")
    lines.append(f"  event offset (s): {event_b_seconds}")
    lines.append(f"  offsetMs:         {clip_b['offset_ms']:.3f}")
    lines.append(f"  uncertaintyMs:    {clip_b['uncertainty_ms']:.3f}")
    lines.append(f"  confidence:       {clip_b['confidence']}")
    lines.append(f"  shared-clock event time: {_ms_to_iso(result['shared_b_ms'])}")
    lines.append("")
    lines.append("Result:")
    lines.append(f"  signed alignment error (A - B): {result['error_ms']:.3f} ms")
    lines.append(
        f"  combined uncertainty (RSS):     {result['combined_uncertainty_ms']:.3f} ms"
    )
    lines.append(
        f"  margin (|error| + uncertainty): {result['margin_ms']:.3f} ms"
    )
    lines.append(f"  threshold:                      {ALIGNMENT_THRESHOLD_MS:.3f} ms")
    lines.append(
        f"  confidence tiers:               A={clip_a['confidence']}, "
        f"B={clip_b['confidence']}"
    )
    verdict = "PASS" if result["passed"] else "FAIL"
    lines.append("")
    lines.append(f"  VERDICT: {verdict}")
    if result["passed"] and (
        clip_a["confidence"] != "green" or clip_b["confidence"] != "green"
    ):
        lines.append(
            "  NOTE: margin passed but at least one clip is not green; treat "
            "this result with caution and prefer re-capturing at green."
        )
    return "\n".join(lines)


def run_self_test() -> int:
    """Validate the math on synthetic in-memory inputs (no files)."""
    # Construct two synthetic sidecars with a KNOWN true alignment.
    #
    # Scenario: a single real-world flash happens at a fixed shared-clock instant.
    # Device A's local clock is 120 ms behind the master (offsetMs = +120) and it
    # started recording at 10:00:00.000Z (its own wall clock); the flash is seen
    # 5.000 s into A's clip.
    # Device B's local clock is 30 ms ahead of the master (offsetMs = -30) and it
    # started recording at 10:00:01.000Z (its own wall clock); the flash is seen
    # 4.000 s into B's clip.
    #
    # Because both clips observe the SAME physical flash and we feed correct
    # offsets, the shared-clock event times must be identical -> error 0 ms.
    clip_a_raw = {
        "mediaPath": "/synthetic/clipA.mp4",
        "deviceId": "synthetic-device-A",
        "startRecordingDate": "2026-06-10T10:00:00.000Z",
        "endRecordingDate": "2026-06-10T10:00:30.000Z",
        "sessionGuid": "synthetic-session",
        "sync": {
            "offsetMs": 120,
            "minRoundTripMs": 8,
            "uncertaintyMs": 6,
            "confidence": "green",
            "sampleCount": 9,
            "calibratedAt": "2026-06-10T09:59:00.000Z",
            "calibrationAgeMs": 60000,
        },
    }
    clip_b_raw = {
        "mediaPath": "/synthetic/clipB.mp4",
        "deviceId": "synthetic-device-B",
        "startRecordingDate": "2026-06-10T10:00:01.000Z",
        "endRecordingDate": "2026-06-10T10:00:31.000Z",
        "sessionGuid": "synthetic-session",
        "sync": {
            "offsetMs": -30,
            "minRoundTripMs": 10,
            "uncertaintyMs": 8,
            "confidence": "green",
            "sampleCount": 7,
            "calibratedAt": "2026-06-10T09:59:00.000Z",
            "calibrationAgeMs": 60000,
        },
    }

    clip_a = extract_clip(clip_a_raw, "self-test clip A")
    clip_b = extract_clip(clip_b_raw, "self-test clip B")

    # Hand-computed expected shared-clock event times (ms since epoch):
    #   A: 10:00:00.000Z + 5.000s + 120ms = 10:00:05.120Z
    #   B: 10:00:01.000Z + 4.000s -  30ms = 10:00:04.970Z ... wait, must match.
    # Construct B's event so the true alignment is exactly 0:
    #   A shared = 10:00:00 + 5.000 + 0.120 = 10:00:05.120
    #   B shared = 10:00:01 + event_b - 0.030  must equal 10:00:05.120
    #   => event_b = 5.120 - 1.000 + 0.030 = 4.150
    event_a = 5.000
    event_b = 4.150

    result = analyze(clip_a, event_a, clip_b, event_b)

    failures: list[str] = []

    if abs(result["error_ms"]) > 1e-6:
        failures.append(
            f"expected ~0 ms alignment error, got {result['error_ms']:.6f} ms"
        )

    expected_combined = math.sqrt(6**2 + 8**2)  # = 10.0
    if abs(result["combined_uncertainty_ms"] - expected_combined) > 1e-6:
        failures.append(
            f"expected combined uncertainty {expected_combined:.6f} ms, "
            f"got {result['combined_uncertainty_ms']:.6f} ms"
        )

    if not result["passed"]:
        failures.append("expected PASS for the zero-error synthetic case")

    # Second synthetic case: inject a deliberate 80 ms true skew that must FAIL.
    skew_clip_b = analyze(clip_a, event_a, clip_b, event_b + 0.080)
    if skew_clip_b["passed"]:
        failures.append("expected FAIL for the 80 ms synthetic skew case")
    if abs(abs(skew_clip_b["error_ms"]) - 80.0) > 1e-6:
        failures.append(
            f"expected ~80 ms error for skew case, got {skew_clip_b['error_ms']:.6f} ms"
        )

    if failures:
        print("self-test FAILED:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print("self-test passed")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Compute cross-device clock-sync alignment error from two media "
            ".sync.json sidecars and an observed synchronized visual event."
        )
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run synthetic in-memory self-tests and exit (no files needed).",
    )
    parser.add_argument("--clip-a", help="Path to device A's <media>.sync.json sidecar.")
    parser.add_argument(
        "--event-a",
        type=float,
        default=0.0,
        help=(
            "Media-relative time (seconds) of the event in clip A. Use 0 for "
            "photos (no recording window). Default: 0."
        ),
    )
    parser.add_argument("--clip-b", help="Path to device B's <media>.sync.json sidecar.")
    parser.add_argument(
        "--event-b",
        type=float,
        default=0.0,
        help=(
            "Media-relative time (seconds) of the event in clip B. Use 0 for "
            "photos (no recording window). Default: 0."
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.self_test:
        return run_self_test()

    if not args.clip_a or not args.clip_b:
        parser.error("--clip-a and --clip-b are required unless --self-test is given")

    try:
        clip_a = extract_clip(load_sidecar(args.clip_a), f"clip A ({args.clip_a})")
        clip_b = extract_clip(load_sidecar(args.clip_b), f"clip B ({args.clip_b})")
    except SyncDataError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    result = analyze(clip_a, args.event_a, clip_b, args.event_b)
    print(render_report(clip_a, args.event_a, clip_b, args.event_b, result))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
