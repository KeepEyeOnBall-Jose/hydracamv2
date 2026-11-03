#!/usr/bin/env python3
"""Summarize uplink_scenarios.py results into one Markdown table plus summary.json.

  python3 scripts/uplink_summarize.py results/uplink

Proxy flows start at 15 s. Loss counters cover 15 s to the end, so they include the slow-start
burst at onset; queue, sojourn and goodput cover 20 s to the end (steady state). Counters come
from MediaMTX /v3/srtconns (receiver) as deltas, summed over reconnects.
MediaMTX (gosrt) counts a gap as Loss, every retransmit as Retrans, and drops (Drop) any
retransmit that arrives after its slot was played out or that duplicates one it already has.
Late original packets are not dropped, only delivered late. So
unrecovered = Loss - (Retrans - Drop): gaps that no retransmit filled in time. Each one breaks
the rest of its GOP (1 s).
Delay estimate = 170 ms phone pipeline (measured G2G minus SRT latency and LAN) + the larger of
the SRT latency and the bottleneck sojourn, plus the 15 ms one-way delay.
"""
import json
import pathlib
import statistics
import sys

LOAD_FROM_S = 20
LOSS_FROM_S = 15
PHONE_PIPELINE_MS = 170
OWD_MS = 15
COUNTERS = ("packetsReceived", "packetsReceivedLoss", "packetsReceivedRetrans",
            "packetsReceivedBelated", "packetsReceivedDrop")


def rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def pct(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(q * len(values)))] if values else None


def summarize(run):
    meta = json.loads((run / "meta.json").read_text())
    all_shaper = rows(run / "shaper.jsonl")
    shaper = [r for r in all_shaper if r["t"] >= LOAD_FROM_S]
    onward = [r["flows"]["srt"] for r in all_shaper if r["t"] > LOSS_FROM_S]
    api = [r for r in rows(run / "api.jsonl") if r["t"] >= LOSS_FROM_S - 1]
    srt = [r["flows"]["srt"] for r in shaper]
    offered = sum(f["offered"] for f in onward)
    link_drops = sum(f["tailDrops"] + f["randomDrops"] for f in onward)
    proxies = sorted(k for k in shaper[0]["flows"] if k.startswith("proxy")) if shaper else []
    goodput = [sum(r["flows"][p].get("goodputKbps", 0) for p in proxies) for r in shaper]
    cbr = [r["flows"]["cbr"] for r in all_shaper if r["t"] > LOSS_FROM_S]
    cbr_offered = sum(f["offered"] for f in cbr)

    # Receiver counters are cumulative per connection id: take last minus first per id.
    first, last, loss_s, seconds, dead_s = {}, {}, 0, 0, 0
    for r in api:
        seconds += r["t"] >= LOSS_FROM_S
        if not r["items"]:
            dead_s += r["t"] >= LOSS_FROM_S
        lost = 0
        for item in r["items"]:
            first.setdefault(item["id"], item)
            lost += item["packetsReceivedLoss"] - last.get(item["id"], item)["packetsReceivedLoss"]
            last[item["id"]] = item
        loss_s += r["t"] >= LOSS_FROM_S and lost > 0
    delta = {c: sum(last[i][c] - first[i][c] for i in last) for c in COUNTERS}
    unrecovered = max(0, delta["packetsReceivedLoss"]
                      - (delta["packetsReceivedRetrans"] - delta["packetsReceivedDrop"]))
    rtt = [i["msRTT"] for r in api if r["t"] >= LOAD_FROM_S for i in r["items"]]
    tsbpd = sorted({i["msReceiveTsbPdDelay"] for r in api for i in r["items"]})
    sojourn_p50 = statistics.median([f["sojournP50Ms"] for f in srt if f["sojournP50Ms"] is not None])
    return {
        "scenario": meta["scenario"], "srtLatencyMs": meta["srtLatencyMs"],
        "shaperArgs": " ".join(meta["shaperArgs"]), "connects": meta.get("connects"),
        "tsbpdMs": tsbpd, "queueP50Ms": pct([r["queueMs"] for r in shaper], 0.5),
        "queueP95Ms": pct([r["queueMs"] for r in shaper], 0.95),
        "srtSojournP50Ms": sojourn_p50,
        "srtLinkDropPct": round(100 * link_drops / offered, 2) if offered else None,
        "rttP50Ms": round(pct(rtt, 0.5)) if rtt else None,
        "lossDetected": delta["packetsReceivedLoss"], "retransReceived": delta["packetsReceivedRetrans"],
        "belated": delta["packetsReceivedBelated"], "dropped": delta["packetsReceivedDrop"],
        "recovered": delta["packetsReceivedLoss"] - unrecovered, "unrecovered": unrecovered,
        "lossSecondsPct": round(100 * loss_s / seconds, 1) if seconds else None,
        "secondsNoPublisher": dead_s,
        "proxyGoodputKbps": round(statistics.mean(goodput)) if proxies else None,
        "proxyBacklogEndKB": sum(shaper[-1]["flows"][p]["backlogKB"] or 0 for p in proxies)
        if proxies and shaper[-1]["flows"][proxies[0]]["backlogKB"] is not None else None,
        "cbrLinkDropPct": round(100 * sum(f["tailDrops"] + f["randomDrops"] for f in cbr) / cbr_offered, 2)
        if cbr_offered else None,
        "g2gEstMs": PHONE_PIPELINE_MS + OWD_MS + round(max(meta["srtLatencyMs"], sojourn_p50)),
    }


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "results/uplink")
    out = [summarize(run) for run in sorted(root.iterdir()) if (run / "meta.json").exists()]
    (root / "summary.json").write_text(json.dumps(out, indent=2) + "\n")
    cols = [("scenario", "Scenario"), ("srtLatencyMs", "L ms"), ("queueP50Ms", "Queue p50 ms"),
            ("queueP95Ms", "Queue p95 ms"), ("srtLinkDropPct", "Link drop %"), ("lossDetected", "Lost"),
            ("recovered", "Recovered"), ("unrecovered", "Unrecovered"),
            ("lossSecondsPct", "Seconds with loss %"), ("connects", "Connects"),
            ("proxyGoodputKbps", "Proxy kbps"), ("proxyBacklogEndKB", "Proxy backlog end KB"),
            ("cbrLinkDropPct", "Cam 2 drop %"), ("g2gEstMs", "G2G est ms")]
    print("| " + " | ".join(h for _, h in cols) + " |")
    print("|" + "---|" * len(cols))
    for s in out:
        print("| " + " | ".join("" if s[k] is None else str(s[k]) for k, _ in cols) + " |")


if __name__ == "__main__":
    main()
