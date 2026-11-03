#!/usr/bin/env python3
"""One H8 scenario on one rooted fleet phone, sampled from the host.

  python3 scripts/fleet_run.py --serial 127.0.0.1:15560 --label s10e --scenario preview \
      --url 'srt://relay:8890?streamid=...' --minutes 20 [--tag toggle-burst --extra '--es toggle burst']

Scenarios: base (master + proxy) and preview (master + proxy + C4 preview). The phone app
writes stats.jsonl/summary.json; this script adds host.jsonl (system CPU, app CPU, thermal
zones, battery, thermal status every 5 s via adb + su) and pulls everything to
results/<label>/<scenario>-<stamp>/.
"""
import argparse
import json
import pathlib
import subprocess
import sys
import time

PKG = "com.amaia23.hydracam.spike.preview"
ACTIVITY = f"{PKG}/.SpikeActivity"
REMOTE_DIR = f"/sdcard/Android/data/{PKG}/files/h8"
REMOTE_SAMPLER = "/data/local/tmp/h8-sample.sh"
SAMPLER = pathlib.Path(__file__).with_name("h8-sample.sh")


def adb(serial, *args, timeout=30):
    return subprocess.run(["adb", "-s", serial, *args], capture_output=True, text=True, timeout=timeout).stdout


def su(serial, command, timeout=30):
    return adb(serial, "shell", f"su -c '{command}'", timeout=timeout)


def sample(serial):
    out = su(serial, f"sh {REMOTE_SAMPLER} {PKG}")
    s = {"t": time.time(), "zones": {}}
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("cpu "):
            s["cpu"] = [int(v) for v in line.split()[1:8]]
        elif line.startswith("pid="):
            s["pid"] = line[4:] or None
        elif line.startswith("zone "):
            name, _, value = line[5:].partition("=")
            if value.lstrip("-").isdigit():
                s["zones"][name] = int(value) / 1000
        elif line.startswith("battery="):
            s["batteryC"] = int(line[8:]) / 10
        elif "Thermal Status" in line:
            s["thermalStatus"] = int(line.rsplit(":", 1)[1])
        elif s.get("pid") and len(line.split()) == 2 and all(v.isdigit() for v in line.split()):
            s["appTicks"] = sum(int(v) for v in line.split())
    return s


def battery_c(serial):
    """Battery °C, or None while adb is unreachable."""
    try:
        return int(su(serial, "cat /sys/class/power_supply/battery/temp").strip() or 0) / 10
    except (subprocess.TimeoutExpired, ValueError):
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serial", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--scenario", choices=["base", "preview"], required=True)
    ap.add_argument("--url", help="publish URL for the preview scenario (omit = encode only)")
    ap.add_argument("--minutes", type=float, default=20)
    ap.add_argument("--master", default="1080p")
    ap.add_argument("--proxy", default="true")
    ap.add_argument("--cool-to", type=float, default=30.0, help="wait until battery <= this (C), max 15 min")
    ap.add_argument("--extra", nargs="*", default=[], help="extra am start args, e.g. --es previewPath gl")
    ap.add_argument("--tag", help="added to the run id, e.g. toggle-burst")
    ap.add_argument("--out", default="results")
    a = ap.parse_args()

    adb(a.serial, "push", str(SAMPLER), REMOTE_SAMPLER)
    deadline = time.time() + 900
    while ((b := battery_c(a.serial)) is None or b > a.cool_to) and time.time() < deadline:
        print(f"[{a.label}] cooling: battery {b} C > {a.cool_to}", flush=True)
        time.sleep(30)

    run_id = "-".join(filter(None, [a.label, a.scenario, a.tag, time.strftime("%Y%m%d-%H%M%S")]))
    duration_s = int(a.minutes * 60) + 10
    args = ["shell", "am", "start", "-n", ACTIVITY, "--es", "run", run_id, "--es", "master", a.master,
            "--ez", "proxy", a.proxy, "--ez", "preview", "true" if a.scenario == "preview" else "false",
            "--ei", "duration", str(duration_s), *a.extra]
    if a.scenario == "preview" and a.url:
        args += ["--es", "url", f"'{a.url}'"]
    adb(a.serial, *args)
    print(f"[{a.label}] started {run_id} for {a.minutes} min", flush=True)

    local = pathlib.Path(a.out) / a.label / run_id
    local.mkdir(parents=True, exist_ok=True)
    with (local / "host.jsonl").open("w") as f:
        end = time.time() + duration_s
        while time.time() < end:
            try:
                f.write(json.dumps(sample(a.serial)) + "\n")
                f.flush()
            except Exception as error:  # noqa: BLE001 - a missed sample is fine
                print(f"[{a.label}] sample failed: {error}", file=sys.stderr, flush=True)
            time.sleep(5)

    for _ in range(30):
        if "summary.json" in adb(a.serial, "shell", "ls", f"{REMOTE_DIR}/{run_id}"):
            break
        time.sleep(2)
    else:
        adb(a.serial, "shell", "am", "start", "-n", ACTIVITY, "--ez", "stop", "true")
        time.sleep(5)
    adb(a.serial, "pull", f"{REMOTE_DIR}/{run_id}/.", str(local), timeout=120)
    print(f"[{a.label}] done -> {local}", flush=True)


if __name__ == "__main__":
    main()
