#!/usr/bin/env python3
"""Report for one screen-off soak run (tool/court_screen_off/soak.sh).

usage: python3 tool/court_screen_off/report.py OUT_DIR

Reads OUT/mock/c1.jsonl (segment events from the phone), OUT/mock/store/**.ts
(uploaded proxy segments) and OUT/samples.txt (phone samples every 10 s). Prints
Markdown and writes OUT/report.json.
"""

import glob
import json
import os
import subprocess
import sys
from collections import defaultdict

FPS = 30


def load_events(out):
    events = []
    path = os.path.join(out, "mock", "c1.jsonl")
    if not os.path.exists(path):
        return events
    with open(path) as handle:
        for line in handle:
            row = json.loads(line)
            if row.get("dir") == "in":
                events.append(row)
    return events


def segment_stats(events):
    by_tier = defaultdict(list)
    gaps = []
    for row in events:
        env = row.get("envelope") or {}
        body = env.get("body") or {}
        if row["type"] == "recording.segment":
            # A durable uploader also re-sends segments left over from an earlier run.
            by_tier[f'{body.get("sessionId", "?")} {body["tier"]}'].append(body)
        elif row["type"] == "recording.gap":
            gaps.append(body)
    tiers = {}
    for tier, segs in by_tier.items():
        segs.sort(key=lambda s: s["seq"])
        seqs = [s["seq"] for s in segs]
        missing_seq = sorted(set(range(seqs[0], seqs[-1] + 1)) - set(seqs))
        frames = sum(s["frames"] for s in segs)
        dur_ms = sum(s["durationMs"] for s in segs)
        span_ms = segs[-1]["mediaStartServerMs"] + segs[-1]["durationMs"] - segs[0]["mediaStartServerMs"]
        holes = []
        for prev, cur in zip(segs, segs[1:]):
            hole = cur["mediaStartServerMs"] - (prev["mediaStartServerMs"] + prev["durationMs"])
            if abs(hole) > 2 * 1000 / FPS:
                holes.append({"afterSeq": prev["seq"], "ms": hole})
        tiers[tier] = {
            "segments": len(segs),
            "missingSeq": missing_seq,
            "frames": frames,
            "durationS": round(dur_ms / 1000, 1),
            "spanS": round(span_ms / 1000, 1),
            "fps": round(frames / (dur_ms / 1000), 2) if dur_ms else None,
            "expectedFrames": round(span_ms / 1000 * FPS),
            "timelineHoles": holes,
        }
    return tiers, gaps


def probe(path):
    """Decode the whole file; return frames, fps and any decoder error output."""
    count = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
         "-show_entries", "stream=nb_read_frames,avg_frame_rate,width,height",
         "-of", "json", path],
        capture_output=True, text=True, timeout=120,
    )
    errors = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "null", "-"],
        capture_output=True, text=True, timeout=300,
    ).stderr.strip()
    stream = (json.loads(count.stdout or "{}").get("streams") or [{}])[0]
    return {
        "frames": int(stream.get("nb_read_frames") or 0),
        "rate": stream.get("avg_frame_rate"),
        "size": f'{stream.get("width")}x{stream.get("height")}',
        "errors": errors,
    }


def decode_stats(out):
    files = sorted(
        glob.glob(os.path.join(out, "mock", "store", "*", "*", "*.ts")),
        key=lambda p: (os.path.dirname(p), int(os.path.basename(p)[:-3])),
    )
    result = {"files": len(files), "frames": 0, "errorFiles": [], "sizes": set()}
    for path in files:
        info = probe(path)
        result["frames"] += info["frames"]
        result["sizes"].add(info["size"])
        if info["errors"] or info["frames"] == 0:
            result["errorFiles"].append({"file": os.path.relpath(path, out), "frames": info["frames"],
                                         "errors": info["errors"][:300]})
    result["sizes"] = sorted(result["sizes"])
    return result


def samples(out):
    rows = []
    path = os.path.join(out, "samples.txt")
    if not os.path.exists(path):
        return rows
    with open(path) as handle:
        for line in handle:
            parts = line.split()
            if not parts:
                continue
            row = {"t": int(parts[0])}
            for part in parts[1:]:
                if "=" in part:
                    key, value = part.split("=", 1)
                    row[key] = value
            rows.append(row)
    return rows


def phase_power(rows):
    phases = defaultdict(list)
    for row in rows:
        phases[row.get("phase", "?")].append(row)
    summary = {}
    for name, group in phases.items():
        currents = [int(r["ma"]) for r in group if r.get("ma", "").lstrip("-").isdigit()]
        caps = [int(r["cap"]) for r in group if r.get("cap", "").isdigit()]
        summary[name] = {
            "samples": len(group),
            "minutes": round((group[-1]["t"] - group[0]["t"]) / 60, 1) if len(group) > 1 else 0,
            "displayStates": sorted({r.get("display", "?") for r in group}),
            "deep": sorted({r.get("deep", "?") for r in group}),
            "slate": sorted({r.get("slate", "?") for r in group}),
            "appAlive": all(r.get("pid") not in (None, "none") for r in group),
            # media.camera lists past clients too, so this is a hint, not proof the camera is open.
            "cameraOpenSamples": sum(1 for r in group if r.get("cam", "0") != "0"),
            "meanCurrentMa": round(sum(currents) / len(currents)) if currents else None,
            "capStart": caps[0] if caps else None,
            "capEnd": caps[-1] if caps else None,
            "brightness": sorted({r.get("bright", "?") for r in group}),
        }
    return summary


def main():
    out = sys.argv[1]
    events = load_events(out)
    tiers, gaps = segment_stats(events)
    decode = decode_stats(out)
    rows = samples(out)
    power = phase_power(rows)
    types = defaultdict(int)
    for row in events:
        types[row["type"]] += 1
    report = {"out": out, "eventTypes": dict(types), "tiers": tiers, "gaps": gaps,
              "decode": decode, "phases": power}
    with open(os.path.join(out, "report.json"), "w") as handle:
        json.dump(report, handle, indent=2)
    device = open(os.path.join(out, "device.txt")).read().split() if os.path.exists(
        os.path.join(out, "device.txt")) else []
    print(f"### {os.path.basename(out)} ({' '.join(device)})\n")
    print("| session tier | segments | missing seq | frames / expected | fps | holes | span s |")
    print("|---|---|---|---|---|---|---|")
    for tier, t in sorted(tiers.items()):
        print(f'| {tier} | {t["segments"]} | {len(t["missingSeq"])} | {t["frames"]} / {t["expectedFrames"]} '
              f'| {t["fps"]} | {len(t["timelineHoles"])} | {t["spanS"]} |')
    print(f'\nrecording.gap events: {len(gaps)}. Uploaded proxy files decoded: {decode["files"]}, '
          f'frames {decode["frames"]}, sizes {decode["sizes"]}, files with errors: {len(decode["errorFiles"])}.\n')
    print("| phase | min | display | deep idle | app alive | camera open samples | mean current mA | battery % |")
    print("|---|---|---|---|---|---|---|---|")
    for name in ("prep", "off", "off-doze", "on", "upload"):
        p = power.get(name)
        if not p:
            continue
        print(f'| {name} | {p["minutes"]} | {",".join(p["displayStates"])} | {",".join(p["deep"])} '
              f'| {p["appAlive"]} | {p["cameraOpenSamples"]}/{p["samples"]} | {p["meanCurrentMa"]} '
              f'| {p["capStart"]}→{p["capEnd"]} |')


if __name__ == "__main__":
    main()
