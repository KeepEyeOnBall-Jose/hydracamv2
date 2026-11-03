#!/usr/bin/env python3
"""Shared-uplink scenarios for the C4 preview, host only (no phone).

Runs on the relay host. Per scenario: a test MediaMTX (internal auth, SRT on 127.0.0.1:18890,
API on 127.0.0.1:19997), uplink_shaper.py in front of it, and ffmpeg publishing a pre-encoded
preview clip (640x360, 20 fps, GOP 1 s, ~900 kbps CBR like the phones' measured rate) over SRT
with stream copy, piped into srt-live-transmit (libsrt; this ffmpeg build has no SRT). The
publisher is restarted when the relay drops it, like the phone's reconnect.
Polls /v3/srtconns/list once a second; srt-live-transmit writes sender stats to sender.jsonl.

  python3 scripts/uplink_scenarios.py --work ~/h8-spike/uplink [--only a-base,c-backlog-l120]
Results: <work>/results/<scenario>/{shaper.jsonl, api.jsonl, publisher.log, meta.json}
"""
import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
LINK4 = ["--rate-kbps", "4000", "--buffer-ms", "500"]
LINK5 = ["--rate-kbps", "5000", "--buffer-ms", "500"]
# name: (srt latency ms, shaper args). Proxy flows start at 15 s; runs last 100 s.
SCENARIOS = {
    "a-base-l120": (120, LINK4),
    "b-segments-l120": (120, LINK4 + ["--proxies", "1", "--proxy-mode", "segments"]),
    "c-backlog-l120": (120, LINK4 + ["--proxies", "1", "--proxy-mode", "backlog"]),
    "d-backlog-l300": (300, LINK4 + ["--proxies", "1", "--proxy-mode", "backlog"]),
    "e-backlog-l1000": (1000, LINK4 + ["--proxies", "1", "--proxy-mode", "backlog"]),
    "f-backlog-shallow-l120": (120, ["--rate-kbps", "4000", "--buffer-ms", "50",
                                     "--proxies", "1", "--proxy-mode", "backlog"]),
    "g-paced2500-l120": (120, LINK4 + ["--proxies", "1", "--proxy-mode", "backlog",
                                       "--pace-kbps", "2500"]),
    "h-2cam-segments-l120": (120, LINK5 + ["--proxies", "2", "--proxy-mode", "segments",
                                           "--cbr-kbps", "950"]),
    "i-2cam-segments-l1000": (1000, LINK5 + ["--proxies", "2", "--proxy-mode", "segments",
                                             "--cbr-kbps", "950"]),
    "j-loss1pct-l120": (120, LINK4 + ["--loss", "0.01"]),
    "k-loss1pct-l300": (300, LINK4 + ["--loss", "0.01"]),
}
DURATION = 100
MEDIAMTX_YML = """\
logLevel: info
authMethod: internal
authInternalUsers:
  - user: any
    pass:
    ips: []
    permissions:
      - action: publish
      - action: read
      - action: api
api: true
apiAddress: 127.0.0.1:19997
metrics: false
pprof: false
playback: false
rtsp: false
rtmp: false
hls: false
webrtc: false
moq: false
srt: true
srtAddress: 127.0.0.1:18890
paths:
  all_others:
"""


def api_conns():
    with urllib.request.urlopen("http://127.0.0.1:19997/v3/srtconns/list", timeout=2) as r:
        return json.load(r)["items"]


def ensure_clip(work):
    clip = work / "preview-640x360-20fps-gop1s.ts"
    if not clip.exists():
        subprocess.run(
            ["nice", "-n", "10", "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=20,noise=alls=12:allf=t",
             "-t", "60", "-threads", "2", "-c:v", "libx264", "-preset", "veryfast", "-tune", "zerolatency",
             "-profile:v", "main", "-pix_fmt", "yuv420p", "-g", "20", "-keyint_min", "20",
             "-sc_threshold", "0", "-bf", "0", "-b:v", "900k", "-minrate", "900k", "-maxrate", "900k",
             "-bufsize", "450k", "-x264-params", "nal-hrd=cbr:force-cfr=1", "-f", "mpegts", str(clip)],
            check=True)
    return clip


def run(work, name, latency_ms, shaper_args, clip):
    out = work / "results" / name
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    (out / "meta.json").write_text(json.dumps(
        {"scenario": name, "srtLatencyMs": latency_ms, "shaperArgs": shaper_args, "durationS": DURATION,
         "started": time.time()}))
    shaper = subprocess.Popen([sys.executable, str(HERE / "uplink_shaper.py"), *shaper_args,
                               "--duration", str(DURATION), "--out", str(out / "shaper.jsonl")])
    time.sleep(0.5)
    t0 = time.monotonic()
    url = f"srt://127.0.0.1:19890?mode=caller&latency={latency_ms}&streamid=publish:h8up/cam1"
    pipeline = (f"nice -n 10 ffmpeg -hide_banner -loglevel warning -re -stream_loop -1 -i '{clip}' -c copy "
                f"-f mpegts - | srt-live-transmit -a:no -q -s:100 -pf:json "
                f"-statsout:'{out}/sender.jsonl' file://con '{url}'")
    log = (out / "publisher.log").open("w")
    publisher, connects = None, 0
    with (out / "api.jsonl").open("w") as api:
        while time.monotonic() - t0 < DURATION - 1:
            if publisher is None or publisher.poll() is not None:
                connects += 1
                log.write(f"{time.monotonic() - t0:.1f} connect #{connects}\n")
                log.flush()
                publisher = subprocess.Popen(["bash", "-c", pipeline], stdout=log, stderr=log,
                                             stdin=subprocess.DEVNULL, start_new_session=True)
            try:
                api.write(json.dumps({"t": round(time.monotonic() - t0, 1), "items": api_conns()}) + "\n")
                api.flush()
            except Exception as error:  # noqa: BLE001 - a missed poll is fine
                print(f"[{name}] api poll failed: {error}", file=sys.stderr)
            time.sleep(1)
    os.killpg(publisher.pid, 15)
    publisher.wait(timeout=5)
    shaper.wait(timeout=10)
    log.close()
    meta = json.loads((out / "meta.json").read_text())
    (out / "meta.json").write_text(json.dumps({**meta, "connects": connects}))
    print(f"[{name}] done, {connects} connect(s)", flush=True)


def main():
    global DURATION
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True, type=pathlib.Path)
    ap.add_argument("--mediamtx", default=str(pathlib.Path.home() / "h8-spike" / "mediamtx"))
    ap.add_argument("--only", help="comma-separated scenario names")
    ap.add_argument("--duration", type=int, default=DURATION, help="seconds per scenario")
    a = ap.parse_args()
    DURATION = a.duration
    a.work.mkdir(parents=True, exist_ok=True)
    clip = ensure_clip(a.work)
    (a.work / "mediamtx-uplink.yml").write_text(MEDIAMTX_YML)
    relay = subprocess.Popen([a.mediamtx, str(a.work / "mediamtx-uplink.yml")],
                             stdout=(a.work / "mediamtx.log").open("w"), stderr=subprocess.STDOUT)
    try:
        for _ in range(50):
            try:
                api_conns()
                break
            except OSError:
                time.sleep(0.2)
        names = a.only.split(",") if a.only else list(SCENARIOS)
        for name in names:
            latency_ms, shaper_args = SCENARIOS[name]
            run(a.work, name, latency_ms, shaper_args, clip)
            time.sleep(3)
    finally:
        relay.terminate()
        relay.wait(timeout=10)
    print("UPLINK-DONE", flush=True)


if __name__ == "__main__":
    main()
