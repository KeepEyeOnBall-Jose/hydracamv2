#!/usr/bin/env python3
"""Markdown table of H8 fleet runs (results/<label>/<run>/ from fleet_run.py).

  python3 scripts/summarize.py results [--viewer .local/viewer.jsonl]

Per run: recorder frames vs expected, PTS gaps, max gap, camera buffer losses; device CPU and
app CPU (host.jsonl, /proc/stat deltas); battery and hottest-zone temperatures; thermal status;
preview fps, publisher drops; viewer arrival / glass-to-glass latency from viewer.jsonl rows
logged inside the run window.
"""
import argparse
import json
import pathlib
import statistics


def jsonl(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def cpu_pcts(host):
    """Device busy % and app % of device between first and last sample with a CPU line."""
    rows = [r for r in host if r.get("cpu")]
    if len(rows) < 2:
        return None, None
    first, last = rows[0], rows[-1]
    total = sum(last["cpu"]) - sum(first["cpu"])
    idle = (last["cpu"][3] + last["cpu"][4]) - (first["cpu"][3] + first["cpu"][4])
    app = None
    with_app = [r for r in rows if "appTicks" in r]
    if len(with_app) >= 2 and total > 0:
        app = 100 * (with_app[-1]["appTicks"] - with_app[0]["appTicks"]) / total
    return (100 * (total - idle) / total if total > 0 else None), app


def temps(host):
    battery = [r["batteryC"] for r in host if "batteryC" in r]
    hottest = [max(r["zones"].values()) for r in host if r.get("zones")]
    status = [r["thermalStatus"] for r in host if "thermalStatus" in r]
    return {
        "batteryStart": battery[0] if battery else None,
        "batteryEnd": battery[-1] if battery else None,
        "batteryMax": max(battery) if battery else None,
        "zoneMax": max(hottest) if hottest else None,
        "thermalMax": max(status) if status else None,
    }


def viewer_latency(viewer, start_ms, end_ms):
    rows = [r for r in viewer if start_ms <= r["t"] <= end_ms]
    arrival = [r["arrivalP50Ms"] for r in rows if r.get("arrivalP50Ms") is not None]
    g2g = [r["g2gP50Ms"] for r in rows if r.get("g2gP50Ms") is not None]
    dropped = max((r.get("framesDropped") or 0 for r in rows), default=None)
    return {
        "arrivalP50": statistics.median(arrival) if arrival else None,
        "g2gP50": statistics.median(g2g) if g2g else None,
        "viewerDropped": dropped,
    }


def fmt(value, digits=0):
    if value is None:
        return "–"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def summarize(run_dir, viewer):
    summary_path = run_dir / "summary.json"
    if not summary_path.exists():
        return None
    s = json.loads(summary_path.read_text())
    stats = jsonl(run_dir / "stats.jsonl")
    host = jsonl(run_dir / "host.jsonl")
    master = s["tracks"].get("master", {})
    preview = s["tracks"].get("preview") or {}
    fps = [r["tracks"]["preview"]["fpsWindow"] for r in stats
           if r.get("tracks", {}).get("preview", {}).get("fpsWindow") is not None]
    device_cpu, app_cpu = cpu_pcts(host)
    start_ms = stats[0]["t"] if stats else s["t"] - s["elapsedS"] * 1_000
    publisher = s.get("publisher") or {}
    return {
        "run": run_dir.name,
        "device": s["device"],
        "path": s["config"].get("previewPath") if s["config"].get("preview") else "–",
        "minutes": s["elapsedS"] / 60,
        "masterFrames": f'{master.get("frames")}/{master.get("expectedFrames")}',
        "masterGaps": master.get("ptsGaps"),
        "masterMaxGapMs": master.get("maxGapMs"),
        "masterBufferLost": master.get("bufferLost"),
        "deviceCpu": device_cpu,
        "appCpu": app_cpu,
        **temps(host),
        "previewFps": statistics.median(fps) if fps else None,
        "previewFrames": f'{preview.get("frames")}/{preview.get("expectedFrames")}' if preview else "–",
        "pubDropped": publisher.get("droppedFrames"),
        **viewer_latency(viewer, start_ms, s["t"]),
    }


COLUMNS = [
    ("run", "run", 0), ("path", "preview path", 0), ("minutes", "min", 1),
    ("masterFrames", "master frames/expected", 0), ("masterGaps", "master PTS gaps", 0),
    ("masterMaxGapMs", "master max gap ms", 0), ("masterBufferLost", "cam buffer lost", 0),
    ("deviceCpu", "device CPU %", 0), ("appCpu", "app CPU % of device", 1),
    ("batteryStart", "battery °C start", 1), ("batteryEnd", "end", 1), ("batteryMax", "max", 1),
    ("zoneMax", "hottest zone °C", 0), ("thermalMax", "thermal status max", 0),
    ("previewFps", "preview fps p50", 1), ("previewFrames", "preview frames/expected", 0),
    ("pubDropped", "publisher dropped", 0), ("arrivalP50", "arrival ms p50", 0),
    ("g2gP50", "g2g ms p50", 0), ("viewerDropped", "viewer dropped", 0),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results", nargs="?", default="results")
    ap.add_argument("--viewer", default=".local/viewer.jsonl")
    a = ap.parse_args()
    viewer = jsonl(pathlib.Path(a.viewer))
    rows = [r for d in sorted(pathlib.Path(a.results).glob("*/*/")) if (r := summarize(d, viewer))]
    by_device = {}
    for row in rows:
        by_device.setdefault(row["device"], []).append(row)
    for device, device_rows in by_device.items():
        print(f"\n### {device}\n")
        print("| " + " | ".join(title for _, title, _ in COLUMNS) + " |")
        print("|" + "---|" * len(COLUMNS))
        for row in device_rows:
            print("| " + " | ".join(fmt(row[key], digits) for key, _, digits in COLUMNS) + " |")


if __name__ == "__main__":
    main()
