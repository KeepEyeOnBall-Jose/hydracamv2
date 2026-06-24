#!/usr/bin/env python3
"""Measure multi-camera clock-sync drift by reading a filmed millisecond clock.

This is the *empirical* counterpart to ``analyze_sync_alignment.py``. Instead of
trusting a human-marked flash event, it reads ground-truth wall-clock epoch
milliseconds straight out of the recorded pixels: every camera films a screen
running ``scripts/clock-sync/clock.html``, which paints a binary strip encoding
``floor(Date.now())`` on each frame. By decoding that strip we know the true
shared-clock instant of every frame, independent of the device's own sync claim.

The filmed clock (authoritative encoding, see ``clock.html``)
-------------------------------------------------------------
A fullscreen page renders one horizontal row of 47 equal-width cells:

  - cell 0       : RED fiducial (solid red, always)  -> strip start.
  - cells 1..44  : DATA, white=1 / black=0, big-endian. cell 1 = bit 43 (MSB),
                   cell 44 = bit 0 (LSB). The 44 bits encode ``floor(Date.now())``
                   (UTC epoch milliseconds) as a 44-bit unsigned integer.
  - cell 45      : PARITY. EVEN parity -- parity is white when the count of 1-bits
                   in the 44 data cells is ODD, so (data ones + parity) is even.
  - cell 46      : GREEN fiducial (solid green, always) -> strip end.

The reader locates the RED and GREEN fiducials by colour, samples the 47 equally
spaced cell centres from the outer-left edge of RED to the outer-right edge of
GREEN, classifies the data cells by luminance, verifies even parity, and rejects
(returns ``None`` for) any frame whose fiducials are missing or whose parity
fails (a torn mid-refresh capture).

Sync model (shared with analyze_sync_alignment.py)
--------------------------------------------------
``offsetMs`` is ``(master_clock - local_clock)`` so ``shared = local + offsetMs``.
For a frame seen ``media_seconds`` into a clip, the device *claims* its shared
clock time is::

    claimed_shared_ms = startRecordingDate_ms + media_seconds*1000 + offsetMs

The *true* shared-clock time is the decoded epoch ms. Per frame::

    error_ms = claimed_shared_ms - true_ms

A near-constant ``error_ms`` across a clip means the device is internally
consistent; the value of that constant versus 0 is the device's absolute sync
error against the real (filmed) clock.

Cross-camera drift for a pair of clips is ``mean_error_A - mean_error_B`` (how
far apart the two cameras place the same true instant on their shared clock).
We combine the clips' sidecar ``uncertaintyMs`` via root-sum-square (reusing the
formula in ``analyze_sync_alignment``) and report::

    margin = |drift| + combined_uncertainty   vs   ALIGNMENT_THRESHOLD_MS (50 ms)

This module imports ``analyze_sync_alignment`` and reuses its sidecar parsing,
the ``analyze()`` alignment formula, and the 50 ms threshold; it does not
re-derive any of that math.

Dependencies: ``cv2`` (opencv) and ``numpy`` for frame decoding, ``ffmpeg`` on
PATH for frame extraction. The decoder/self-test path requires only cv2+numpy.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import subprocess
import sys
import tempfile
from itertools import combinations
from pathlib import Path
from typing import Any, NamedTuple, Optional

# --- Reuse the sibling tool's math (do NOT duplicate the alignment formula) ---
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
try:
    import analyze_sync_alignment as asa  # noqa: E402
except ImportError as exc:  # pragma: no cover - defensive import guard
    raise SystemExit(
        "error: could not import analyze_sync_alignment.py. This tool must live "
        "in scripts/clock-sync/ alongside its parent scripts/ directory.\n"
        f"  import error: {exc}"
    )

# --- Guarded heavy imports: cv2 + numpy ---
try:
    import cv2  # noqa: E402
    import numpy as np  # noqa: E402
except ImportError as exc:  # pragma: no cover - exercised only without deps
    raise SystemExit(
        "error: this tool requires opencv (cv2) and numpy.\n"
        "  Use the cv-compute virtualenv, e.g.\n"
        "    /Users/jose/src/work/media-timeline/services/cv-compute/.venv/bin/python "
        f"{Path(__file__).name} --self-test\n"
        "  or install deps:  pip install opencv-python numpy\n"
        f"  import error: {exc}"
    )


# Encoding constants (must match clock.html).
DATA_BITS = 44
N_CELLS = 47  # RED + 44 data + PARITY + GREEN
RED_INDEX = 0
DATA_START_INDEX = 1
PARITY_INDEX = 45
GREEN_INDEX = 46

ALIGNMENT_THRESHOLD_MS = asa.ALIGNMENT_THRESHOLD_MS


class DecodeError(Exception):
    """Raised for unrecoverable decoder configuration problems (not bad frames)."""


# --------------------------------------------------------------------------- #
# Decoder
# --------------------------------------------------------------------------- #


def _find_color_mask(bgr: "np.ndarray", which: str) -> "np.ndarray":
    """Return a boolean mask of strongly red or green pixels.

    Works in BGR (opencv default). A pixel is "red" when its red channel
    dominates both other channels by a margin; "green" symmetrically. Thresholds
    are deliberately loose to tolerate screen glare / mild colour shift.
    """
    b = bgr[:, :, 0].astype(np.int16)
    g = bgr[:, :, 1].astype(np.int16)
    r = bgr[:, :, 2].astype(np.int16)
    margin = 50
    floor = 90
    if which == "red":
        return (r > floor) & (r - g > margin) & (r - b > margin)
    if which == "green":
        return (g > floor) & (g - r > margin) & (g - b > margin)
    raise DecodeError(f"unknown colour {which!r}")


def _largest_blob_centroid(mask: "np.ndarray") -> Optional[tuple[float, float, float]]:
    """Return (cx, cy, width) of the largest connected blob in a boolean mask.

    ``width`` is the bounding-box width of that blob (used to size the strip).
    Returns None when no blob is present.
    """
    mask_u8 = mask.astype(np.uint8)
    num, labels, stats, centroids = cv2.connectedComponentsWithStats(mask_u8, connectivity=8)
    if num <= 1:
        return None
    # Label 0 is background; pick the largest remaining by area.
    best_label = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    cx, cy = centroids[best_label]
    width = float(stats[best_label, cv2.CC_STAT_WIDTH])
    area = int(stats[best_label, cv2.CC_STAT_AREA])
    if area < 4:
        return None
    return float(cx), float(cy), width


def _luma(bgr_pixel: "np.ndarray") -> float:
    """Rec.601 luma of a BGR pixel (or small patch mean already reduced)."""
    b, g, r = float(bgr_pixel[0]), float(bgr_pixel[1]), float(bgr_pixel[2])
    return 0.114 * b + 0.587 * g + 0.299 * r


def decode_strip(frame_bgr: "np.ndarray") -> Optional[int]:
    """Decode the epoch milliseconds from one BGR frame, or None if rejected.

    Steps:
      1. Find the RED and GREEN fiducial blobs by colour.
      2. Orient the strip RED -> GREEN (reverse if the image is flipped so that
         green sits left of red).
      3. From RED's outer-left edge to GREEN's outer-right edge, sample 47
         equally spaced cell centres along the strip axis.
      4. Classify the 44 data cells by luminance, decode the big-endian int,
         verify even parity. Reject on any failure.
    """
    if frame_bgr is None or frame_bgr.ndim != 3:
        return None
    h, w = frame_bgr.shape[:2]

    red = _largest_blob_centroid(_find_color_mask(frame_bgr, "red"))
    green = _largest_blob_centroid(_find_color_mask(frame_bgr, "green"))
    if red is None or green is None:
        return None

    red_cx, red_cy, red_w = red
    green_cx, green_cy, green_w = green

    # The strip is roughly horizontal (cameras point straight down). Require the
    # two fiducials to sit on a near-horizontal line relative to their span.
    span = math.hypot(green_cx - red_cx, green_cy - red_cy)
    if span < 4.0:
        return None
    # Cell pitch ~ span / (N_CELLS - 1). The fiducial centroid-to-centroid
    # distance covers (N_CELLS - 1) cell pitches.
    pitch_x = (green_cx - red_cx) / (N_CELLS - 1)
    pitch_y = (green_cy - red_cy) / (N_CELLS - 1)

    # Sample each of the 47 cell centres (RED at i=0 .. GREEN at i=46).
    def cell_center(i: int) -> tuple[int, int]:
        cx = red_cx + pitch_x * i
        cy = red_cy + pitch_y * i
        return int(round(cx)), int(round(cy))

    # Confirm orientation using the fiducial colours at the predicted endpoints.
    # If the strip is horizontally flipped, red is to the right of green; detect
    # by sampling and, if needed, reverse the cell ordering.
    def sample_patch(cx: int, cy: int) -> Optional["np.ndarray"]:
        # Average a small patch (a third of a cell) to resist blur / noise.
        rad = max(1, int(round(min(abs(pitch_x), span / (N_CELLS - 1)) / 3)))
        x0, x1 = max(0, cx - rad), min(w, cx + rad + 1)
        y0, y1 = max(0, cy - rad), min(h, cy + rad + 1)
        if x0 >= x1 or y0 >= y1:
            return None
        patch = frame_bgr[y0:y1, x0:x1].reshape(-1, 3).astype(np.float64)
        return patch.mean(axis=0)

    order = list(range(N_CELLS))

    def classify_cells(cell_order: list[int]) -> Optional[int]:
        # Verify fiducials at the canonical endpoints/parity-neighbour positions.
        first = sample_patch(*cell_center(cell_order[RED_INDEX]))
        last = sample_patch(*cell_center(cell_order[GREEN_INDEX]))
        if first is None or last is None:
            return None
        fb, fg, fr = first
        lb, lg, lr = last
        red_ok = fr > fg + 30 and fr > fb + 30
        green_ok = lg > lr + 30 and lg > lb + 30
        if not (red_ok and green_ok):
            return None

        ones = 0
        value = 0
        for k in range(DATA_BITS):
            cell_i = cell_order[DATA_START_INDEX + k]
            patch = sample_patch(*cell_center(cell_i))
            if patch is None:
                return None
            bit = 1 if _luma(patch) >= 128.0 else 0
            value = (value << 1) | bit  # k=0 is MSB (bit 43)
            ones += bit

        parity_patch = sample_patch(*cell_center(cell_order[PARITY_INDEX]))
        if parity_patch is None:
            return None
        parity_bit = 1 if _luma(parity_patch) >= 128.0 else 0
        # EVEN parity: total ones (data + parity) must be even.
        if (ones + parity_bit) % 2 != 0:
            return None
        return value

    decoded = classify_cells(order)
    if decoded is not None:
        return decoded
    # Orientation fallback: image flipped so green is left of red. Reverse.
    return classify_cells(list(reversed(order)))


# --------------------------------------------------------------------------- #
# Frame extraction (ffmpeg)
# --------------------------------------------------------------------------- #


def _ensure_ffmpeg() -> None:
    try:
        subprocess.run(
            ["ffmpeg", "-version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise DecodeError(
            "ffmpeg not found on PATH; install ffmpeg to extract frames"
        ) from exc


class FrameSample(NamedTuple):
    media_seconds: float
    decoded_epoch_ms: int


def extract_and_decode(video_path: str, sample_fps: float) -> list[FrameSample]:
    """Extract frames at ``sample_fps`` via ffmpeg and decode each one.

    media_seconds for frame index ``n`` (0-based, as emitted by the fps filter)
    is ``n / sample_fps``. Returns only the frames that decode successfully.
    """
    _ensure_ffmpeg()
    if not Path(video_path).exists():
        raise DecodeError(f"video not found: {video_path}")
    if sample_fps <= 0:
        raise DecodeError("--fps must be positive")

    samples: list[FrameSample] = []
    with tempfile.TemporaryDirectory(prefix="clockdrift_") as tmp:
        pattern = str(Path(tmp) / "frame_%06d.png")
        cmd = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            video_path,
            "-vf",
            f"fps={sample_fps}",
            "-vsync",
            "0",
            pattern,
        ]
        try:
            subprocess.run(cmd, check=True, stderr=subprocess.PIPE)
        except subprocess.CalledProcessError as exc:
            detail = exc.stderr.decode("utf-8", "replace") if exc.stderr else ""
            raise DecodeError(f"ffmpeg failed extracting frames: {detail}") from exc

        frame_files = sorted(Path(tmp).glob("frame_*.png"))
        for idx, frame_file in enumerate(frame_files):
            img = cv2.imread(str(frame_file), cv2.IMREAD_COLOR)
            if img is None:
                continue
            decoded = decode_strip(img)
            if decoded is None:
                continue
            # ffmpeg fps filter emits frame n at media time n / fps.
            samples.append(FrameSample(idx / sample_fps, decoded))
    return samples


# --------------------------------------------------------------------------- #
# Per-clip and pairwise analysis
# --------------------------------------------------------------------------- #


def clip_error_series(
    clip: dict[str, Any], samples: list[FrameSample]
) -> list[float]:
    """Per-frame error_ms = claimed_shared_ms - true_ms for one clip.

    claimed_shared_ms reuses the parent tool's shared-clock model via
    ``analyze_sync_alignment.shared_clock_event_ms`` with event_seconds set to
    the frame's media_seconds.
    """
    errors: list[float] = []
    for sample in samples:
        claimed = asa.shared_clock_event_ms(clip, sample.media_seconds)
        errors.append(claimed - float(sample.decoded_epoch_ms))
    return errors


def summarize_errors(errors: list[float]) -> dict[str, Any]:
    """mean/median/stdev/n summary of an error series."""
    n = len(errors)
    if n == 0:
        return {"n": 0, "mean_ms": None, "median_ms": None, "stdev_ms": None}
    return {
        "n": n,
        "mean_ms": statistics.fmean(errors),
        "median_ms": statistics.median(errors),
        "stdev_ms": statistics.pstdev(errors) if n > 1 else 0.0,
    }


def combined_uncertainty(clip_a: dict[str, Any], clip_b: dict[str, Any]) -> float:
    """RSS of two clips' sidecar uncertainties (same combination as parent tool)."""
    return math.sqrt(clip_a["uncertainty_ms"] ** 2 + clip_b["uncertainty_ms"] ** 2)


def pairwise_drift(
    clip_a: dict[str, Any],
    summary_a: dict[str, Any],
    clip_b: dict[str, Any],
    summary_b: dict[str, Any],
) -> dict[str, Any]:
    """Relative drift = mean_error_A - mean_error_B with PASS/FAIL margin."""
    mean_a = summary_a["mean_ms"]
    mean_b = summary_b["mean_ms"]
    if mean_a is None or mean_b is None:
        return {
            "drift_ms": None,
            "combined_uncertainty_ms": combined_uncertainty(clip_a, clip_b),
            "margin_ms": None,
            "passed": False,
            "reason": "insufficient decoded frames in one or both clips",
        }
    drift = mean_a - mean_b
    comb = combined_uncertainty(clip_a, clip_b)
    margin = abs(drift) + comb
    return {
        "drift_ms": drift,
        "combined_uncertainty_ms": comb,
        "margin_ms": margin,
        "passed": margin < ALIGNMENT_THRESHOLD_MS,
        "reason": None,
    }


def interpolate_media_seconds_at_epoch(
    samples: list[FrameSample], target_epoch_ms: float
) -> Optional[float]:
    """media_seconds where the decoded clock equals ``target_epoch_ms``.

    Linearly interpolates between the two bracketing decoded frames. Returns None
    if the target lies outside the clip's decoded range. This produces the
    event-seconds that ``analyze_sync_alignment.analyze()`` consumes, so a human
    can cross-check against the existing tool.
    """
    if len(samples) < 2:
        return None
    ordered = sorted(samples, key=lambda s: s.decoded_epoch_ms)
    lo_ms = ordered[0].decoded_epoch_ms
    hi_ms = ordered[-1].decoded_epoch_ms
    if not (lo_ms <= target_epoch_ms <= hi_ms):
        return None
    for prev, nxt in zip(ordered, ordered[1:]):
        if prev.decoded_epoch_ms <= target_epoch_ms <= nxt.decoded_epoch_ms:
            span = nxt.decoded_epoch_ms - prev.decoded_epoch_ms
            if span == 0:
                return prev.media_seconds
            frac = (target_epoch_ms - prev.decoded_epoch_ms) / span
            return prev.media_seconds + frac * (nxt.media_seconds - prev.media_seconds)
    return None


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #


class LoadedClip(NamedTuple):
    label: str
    video_path: str
    sidecar_path: str
    clip: dict[str, Any]
    samples: list[FrameSample]
    summary: dict[str, Any]


def process_clips(
    clip_args: list[tuple[str, str]], sample_fps: float
) -> list[LoadedClip]:
    loaded: list[LoadedClip] = []
    for idx, (video_path, sidecar_path) in enumerate(clip_args):
        label = f"clip{idx + 1}"
        clip = asa.extract_clip(
            asa.load_sidecar(sidecar_path), f"{label} ({sidecar_path})"
        )
        samples = extract_and_decode(video_path, sample_fps)
        summary = summarize_errors(clip_error_series(clip, samples))
        loaded.append(
            LoadedClip(label, video_path, sidecar_path, clip, samples, summary)
        )
    return loaded


def common_target_epoch(loaded: list[LoadedClip]) -> Optional[float]:
    """An epoch ms inside every clip's decoded range (midpoint of the overlap)."""
    ranges: list[tuple[int, int]] = []
    for lc in loaded:
        if len(lc.samples) < 2:
            return None
        epochs = [s.decoded_epoch_ms for s in lc.samples]
        ranges.append((min(epochs), max(epochs)))
    lo = max(r[0] for r in ranges)
    hi = min(r[1] for r in ranges)
    if lo > hi:
        return None
    return (lo + hi) / 2.0


def build_report(
    loaded: list[LoadedClip], sample_fps: float
) -> tuple[str, dict[str, Any], bool]:
    lines: list[str] = []
    lines.append("HydraCam clock-drift-from-frames analysis")
    lines.append("=" * 52)
    lines.append(f"sample fps: {sample_fps}")
    lines.append(f"alignment threshold: {ALIGNMENT_THRESHOLD_MS:.3f} ms")
    lines.append("")

    clip_json: list[dict[str, Any]] = []
    for lc in loaded:
        lines.append(f"{lc.label}:")
        lines.append(f"  video:         {lc.video_path}")
        lines.append(f"  sidecar:       {lc.sidecar_path}")
        lines.append(f"  deviceId:      {lc.clip.get('device_id')}")
        lines.append(f"  {lc.clip['date_field']}: {lc.clip['start'].isoformat()}")
        lines.append(f"  offsetMs:      {lc.clip['offset_ms']:.3f}")
        lines.append(f"  uncertaintyMs: {lc.clip['uncertainty_ms']:.3f}")
        lines.append(f"  confidence:    {lc.clip['confidence']}")
        s = lc.summary
        lines.append(f"  decoded frames (n): {s['n']}")
        if s["n"]:
            lines.append(
                f"  error_ms vs true clock: mean={s['mean_ms']:.3f} "
                f"median={s['median_ms']:.3f} stdev={s['stdev_ms']:.3f}"
            )
        else:
            lines.append("  error_ms vs true clock: <no frames decoded>")
        lines.append("")
        clip_json.append(
            {
                "label": lc.label,
                "video": lc.video_path,
                "sidecar": lc.sidecar_path,
                "device_id": lc.clip.get("device_id"),
                "offset_ms": lc.clip["offset_ms"],
                "uncertainty_ms": lc.clip["uncertainty_ms"],
                "confidence": lc.clip["confidence"],
                "summary": s,
            }
        )

    # Pairwise drift.
    lines.append("Pairwise cross-camera drift:")
    pairs_json: list[dict[str, Any]] = []
    all_passed = True
    has_pair = False
    for a, b in combinations(loaded, 2):
        has_pair = True
        result = pairwise_drift(a.clip, a.summary, b.clip, b.summary)
        verdict = "PASS" if result["passed"] else "FAIL"
        if not result["passed"]:
            all_passed = False
        lines.append(f"  {a.label} vs {b.label}:")
        if result["drift_ms"] is None:
            lines.append(f"    drift: <{result['reason']}>")
        else:
            lines.append(f"    drift (meanErr_A - meanErr_B): {result['drift_ms']:.3f} ms")
            lines.append(
                f"    combined uncertainty (RSS):    {result['combined_uncertainty_ms']:.3f} ms"
            )
            lines.append(f"    margin (|drift| + uncertainty): {result['margin_ms']:.3f} ms")
        lines.append(f"    VERDICT: {verdict}")
        pairs_json.append(
            {
                "clip_a": a.label,
                "clip_b": b.label,
                **{k: v for k, v in result.items()},
            }
        )
    if not has_pair:
        lines.append("  <need at least 2 clips for pairwise drift>")
    lines.append("")

    # Cross-check: event-seconds at a common epoch for analyze_sync_alignment.
    lines.append("Cross-check (event-seconds for analyze_sync_alignment.py):")
    target = common_target_epoch(loaded)
    crosscheck_json: dict[str, Any] = {"target_epoch_ms": target, "clips": []}
    if target is None:
        lines.append("  <no epoch ms common to all clips>")
    else:
        lines.append(f"  target true epoch ms: {target:.1f} ({asa._ms_to_iso(target)})")
        for lc in loaded:
            es = interpolate_media_seconds_at_epoch(lc.samples, target)
            if es is None:
                lines.append(f"    {lc.label}: <target outside decoded range>")
            else:
                lines.append(f"    {lc.label}: --event-{lc.label} {es:.6f}")
            crosscheck_json["clips"].append(
                {"label": lc.label, "event_seconds": es}
            )
    lines.append("")

    overall = all_passed and has_pair
    lines.append(f"OVERALL: {'PASS' if overall else 'FAIL'}")

    summary_json = {
        "sample_fps": sample_fps,
        "alignment_threshold_ms": ALIGNMENT_THRESHOLD_MS,
        "clips": clip_json,
        "pairs": pairs_json,
        "crosscheck": crosscheck_json,
        "overall_passed": overall,
    }
    # If there are no pairs we cannot fail on the drift criterion; treat single
    # clip as informational (not a failure) for exit-code purposes.
    exit_pass = all_passed
    return "\n".join(lines), summary_json, exit_pass


# --------------------------------------------------------------------------- #
# Self-test (no camera / ffmpeg required)
# --------------------------------------------------------------------------- #


def render_strip_image(
    epoch_ms: int,
    *,
    cell_px: int = 24,
    height_px: int = 80,
    x_offset: int = 30,
    y_offset: int = 25,
    canvas_w: int = 47 * 24 + 120,
    canvas_h: int = 130,
    corrupt_parity: bool = False,
    flip_horizontal: bool = False,
) -> "np.ndarray":
    """Render a synthetic 47-cell strip onto a black canvas (BGR).

    Mirrors clock.html exactly: RED, 44 big-endian data cells (MSB left),
    EVEN-parity cell, GREEN. Optionally corrupt the parity cell or flip the
    whole image horizontally to exercise decoder robustness.
    """
    canvas = np.zeros((canvas_h, canvas_w, 3), dtype=np.uint8)

    # Compute bits MSB-first.
    bits = [(epoch_ms >> (DATA_BITS - 1 - k)) & 1 for k in range(DATA_BITS)]
    ones = sum(bits)
    parity = ones % 2  # EVEN parity (white when data ones are odd)
    if corrupt_parity:
        parity ^= 1

    def paint(cell_index: int, color_bgr: tuple[int, int, int]) -> None:
        x0 = x_offset + cell_index * cell_px
        x1 = x0 + cell_px
        y0 = y_offset
        y1 = y0 + height_px
        canvas[y0:y1, x0:x1] = color_bgr

    paint(RED_INDEX, (0, 0, 255))  # red (BGR)
    for k in range(DATA_BITS):
        shade = (255, 255, 255) if bits[k] else (0, 0, 0)
        paint(DATA_START_INDEX + k, shade)
    paint(PARITY_INDEX, (255, 255, 255) if parity else (0, 0, 0))
    paint(GREEN_INDEX, (0, 255, 0))  # green (BGR)

    if flip_horizontal:
        canvas = canvas[:, ::-1, :].copy()
    return canvas


def _synthetic_clip(start_iso: str, offset_ms: float, uncertainty_ms: float) -> dict[str, Any]:
    raw = {
        "mediaPath": f"/synthetic/{start_iso}.mp4",
        "deviceId": f"dev-{offset_ms}",
        "startRecordingDate": start_iso,
        "endRecordingDate": start_iso,
        "sync": {
            "offsetMs": offset_ms,
            "minRoundTripMs": 8,
            "uncertaintyMs": uncertainty_ms,
            "confidence": "green",
            "sampleCount": 9,
            "calibratedAt": start_iso,
            "calibrationAgeMs": 0,
        },
    }
    return asa.extract_clip(raw, "self-test synthetic clip")


def run_self_test() -> int:
    failures: list[str] = []

    # (a) Decoder round-trips on several known epoch ms values.
    known_values = [
        0,
        1,
        1_718_000_000_000,  # ~2024
        1_750_000_000_123,  # within sampling range used below
        (1 << DATA_BITS) - 1,  # all-ones data
        0b101010101010101010101010101010101010101010 & ((1 << DATA_BITS) - 1),
    ]
    for value in known_values:
        img = render_strip_image(value)
        decoded = decode_strip(img)
        if decoded != value:
            failures.append(f"decoder: expected {value}, got {decoded}")

    # Parity-corrupted image must be rejected.
    bad = render_strip_image(1_750_000_000_123, corrupt_parity=True)
    if decode_strip(bad) is not None:
        failures.append("decoder: parity-corrupted frame was NOT rejected")

    # Horizontally flipped image must still decode.
    flipped_value = 1_750_000_000_456
    flipped = render_strip_image(flipped_value, flip_horizontal=True)
    decoded_flip = decode_strip(flipped)
    if decoded_flip != flipped_value:
        failures.append(
            f"decoder: flipped frame expected {flipped_value}, got {decoded_flip}"
        )

    # Mild blur must still decode.
    blurry = cv2.GaussianBlur(render_strip_image(1_750_000_000_789), (5, 5), 0)
    if decode_strip(blurry) != 1_750_000_000_789:
        failures.append("decoder: mildly blurred frame failed to decode")

    # (b) Pairwise drift math with a KNOWN injected drift.
    #
    # Build two in-memory clip series sharing the SAME true clock. Both start at
    # 10:00:00.000Z. We pick true epoch ms = start_ms + media_seconds*1000 for a
    # range of frames, then craft offsets so the per-clip mean error is a known
    # constant and the pairwise drift is a known value.
    #
    # error_ms = (start_ms + media_s*1000 + offsetMs) - true_ms.
    # With true_ms == start_ms + media_s*1000, error_ms == offsetMs for EVERY
    # frame. So mean_error_A == offset_A and mean_error_B == offset_B, and
    # drift == offset_A - offset_B.
    start_iso = "2026-06-10T10:00:00.000Z"
    start_ms = asa._parse_iso8601_utc(start_iso).timestamp() * 1000.0

    fps = 10.0
    n_frames = 30
    samples = [
        FrameSample(i / fps, int(round(start_ms + (i / fps) * 1000.0)))
        for i in range(n_frames)
    ]

    # PASS pair: offsets 12 and -8 -> drift 20 ms, uncertainty RSS sqrt(6^2+8^2)=10
    # margin = 30 < 50 -> PASS.
    clip_pass_a = _synthetic_clip(start_iso, 12.0, 6.0)
    clip_pass_b = _synthetic_clip(start_iso, -8.0, 8.0)
    sum_pa = summarize_errors(clip_error_series(clip_pass_a, samples))
    sum_pb = summarize_errors(clip_error_series(clip_pass_b, samples))
    if abs(sum_pa["mean_ms"] - 12.0) > 1e-6:
        failures.append(f"drift: expected mean_error_A=12, got {sum_pa['mean_ms']}")
    if abs(sum_pb["mean_ms"] - (-8.0)) > 1e-6:
        failures.append(f"drift: expected mean_error_B=-8, got {sum_pb['mean_ms']}")
    res_pass = pairwise_drift(clip_pass_a, sum_pa, clip_pass_b, sum_pb)
    if abs(res_pass["drift_ms"] - 20.0) > 1e-6:
        failures.append(f"drift: expected drift 20 ms, got {res_pass['drift_ms']}")
    if abs(res_pass["combined_uncertainty_ms"] - 10.0) > 1e-6:
        failures.append(
            f"drift: expected combined uncertainty 10 ms, got "
            f"{res_pass['combined_uncertainty_ms']}"
        )
    if not res_pass["passed"]:
        failures.append("drift: expected PASS for 20 ms drift / 10 ms uncertainty")

    # FAIL pair: offsets 60 and -10 -> drift 70 ms -> margin > 50 -> FAIL.
    clip_fail_a = _synthetic_clip(start_iso, 60.0, 6.0)
    clip_fail_b = _synthetic_clip(start_iso, -10.0, 8.0)
    sum_fa = summarize_errors(clip_error_series(clip_fail_a, samples))
    sum_fb = summarize_errors(clip_error_series(clip_fail_b, samples))
    res_fail = pairwise_drift(clip_fail_a, sum_fa, clip_fail_b, sum_fb)
    if abs(res_fail["drift_ms"] - 70.0) > 1e-6:
        failures.append(f"drift: expected drift 70 ms, got {res_fail['drift_ms']}")
    if res_fail["passed"]:
        failures.append("drift: expected FAIL for 70 ms drift")

    # Cross-check interpolation recovers a known media_seconds.
    target = start_ms + 1.5 * 1000.0  # 1.5 s in
    es = interpolate_media_seconds_at_epoch(samples, target)
    if es is None or abs(es - 1.5) > 1e-6:
        failures.append(f"crosscheck: expected event_seconds 1.5, got {es}")

    if failures:
        print("self-test FAILED:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print("self-test passed")
    return 0


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def _parse_clip_arg(value: str) -> tuple[str, str]:
    """Parse a --clip VIDEO:SIDECAR argument.

    Splits on the LAST ':' that is not part of a Windows drive letter, so paths
    with colons inside are unlikely; we recommend POSIX paths. Uses rsplit to
    keep the sidecar (typically <video>.sync.json) intact.
    """
    if ":" not in value:
        raise argparse.ArgumentTypeError(
            f"--clip expects VIDEO:SIDECAR, missing ':' in {value!r}"
        )
    video, sidecar = value.rsplit(":", 1)
    if not video or not sidecar:
        raise argparse.ArgumentTypeError(
            f"--clip expects non-empty VIDEO and SIDECAR, got {value!r}"
        )
    return video, sidecar


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Measure multi-camera clock-sync drift by decoding a filmed "
            "millisecond clock (clock.html) from recorded frames."
        )
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Render synthetic strips + synthetic clip series, validate the "
        "decoder and drift math, then exit (no camera/ffmpeg needed).",
    )
    parser.add_argument(
        "--clip",
        action="append",
        type=_parse_clip_arg,
        metavar="VIDEO:SIDECAR",
        help="A clip as VIDEO:SIDECAR (path to recording : path to .sync.json). "
        "Repeatable; provide >=2 for cross-camera drift.",
    )
    parser.add_argument(
        "--fps",
        type=float,
        default=10.0,
        help="Frame sampling rate passed to ffmpeg (frames/sec). Default: 10.",
    )
    parser.add_argument(
        "--json-out",
        metavar="PATH",
        help="Write the machine-readable summary JSON to PATH.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.self_test:
        return run_self_test()

    if not args.clip:
        parser.error("provide at least one --clip VIDEO:SIDECAR (or use --self-test)")

    try:
        loaded = process_clips(args.clip, args.fps)
    except (asa.SyncDataError, DecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    report, summary_json, exit_pass = build_report(loaded, args.fps)
    print(report)

    if args.json_out:
        try:
            Path(args.json_out).write_text(
                json.dumps(summary_json, indent=2), encoding="utf-8"
            )
        except OSError as exc:
            print(f"error: could not write --json-out {args.json_out}: {exc}", file=sys.stderr)
            return 2

    return 0 if exit_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
