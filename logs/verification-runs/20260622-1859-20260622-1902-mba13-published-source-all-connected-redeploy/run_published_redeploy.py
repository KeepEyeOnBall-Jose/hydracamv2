#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess
import sys


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    print("+ " + " ".join(command), flush=True)
    return subprocess.run(command, text=True, check=False, **kwargs)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: run_published_redeploy.py <evidence-run-dir>", file=sys.stderr)
        return 2

    run_dir = pathlib.Path(sys.argv[1]).resolve()
    local_logs = run_dir / "device-logs" / "published-source-redeploy"
    local_logs.mkdir(parents=True, exist_ok=True)

    remote_dir = "/tmp/hydracam-published-source-all-connected-redeploy"
    remote_script = r"""#!/usr/bin/env bash
set -u

ADB=/Users/jose/Library/Android/sdk/platform-tools/adb
FLUTTER=/Users/jose/development/flutter/bin/flutter
PUBLISHED=/Users/jose/src/work/hydracamv2-published
APK="$PUBLISHED/build/app/outputs/flutter-apk/app-debug.apk"
IOS_APP=/Users/jose/src/work/hydracamv2-mba13-deploy/build/ios-mba13-transfer-profile/Build/Products/Profile-iphoneos/Runner.app
IOS_BUNDLE=com.keepeyeonball
RUN=/tmp/hydracam-published-source-all-connected-redeploy

rm -rf "$RUN"
mkdir -p "$RUN"

{
  echo "REMOTE_RUN_DIR=$RUN"
  echo "SOURCE_COMMIT=$(git -C "$PUBLISHED" rev-parse HEAD)"
  echo "SOURCE_STATUS=$(git -C "$PUBLISHED" status -sb)"
  echo "APK=$APK"
  ls -lh "$APK"
  shasum -a 256 "$APK"
  echo "IOS_APP=$IOS_APP"
  ls -ld "$IOS_APP"
  codesign -dv "$IOS_APP" 2>&1 || true
  echo "CODESIGN_IDENTITIES"
  security find-identity -p codesigning -v || true
  echo "FLUTTER_DEVICES"
  "$FLUTTER" devices --device-timeout 10 || true
} > "$RUN/source-and-host.txt" 2>&1

echo "START_ALL=$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$RUN/batch.txt"
pids=""

deploy_android() {
  local serial="$1"
  (
    set -e
    echo "TARGET_START android $serial $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "APK_SHA"
    shasum -a 256 "$APK"
    "$ADB" -s "$serial" install -r "$APK" || "$ADB" -s "$serial" install --no-streaming -r "$APK"
    "$ADB" -s "$serial" shell am force-stop com.amaia23.hydracam || true
    "$ADB" -s "$serial" shell am start -n com.amaia23.hydracam/.MainActivity
    sleep 3
    printf "PID="
    "$ADB" -s "$serial" shell pidof com.amaia23.hydracam | tr -d "\r"
    "$ADB" -s "$serial" shell dumpsys package com.amaia23.hydracam | egrep "versionName|versionCode|firstInstallTime|lastUpdateTime"
    "$ADB" -s "$serial" logcat -d -t 500 > "$RUN/$serial-logcat.txt" || true
    echo "TARGET_END android $serial $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ) > "$RUN/$serial.log" 2>&1 &
  pids="$pids $!"
}

deploy_ios() {
  local device="$1"
  (
    set -e
    echo "TARGET_START ios $device $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    xcrun devicectl device install app --device "$device" "$IOS_APP"
    xcrun devicectl device process launch \
      --device "$device" \
      --terminate-existing "$IOS_BUNDLE" \
      --timeout 60 \
      --json-output "$RUN/$device-launch.json" \
      --log-output "$RUN/$device-launch-xcode.log"
    python3 - "$RUN/$device-launch.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
process = data.get("result", {}).get("process", {})
print("PID=%s" % process.get("processIdentifier"))
print("EXEC=%s" % process.get("executable"))
PY
    echo "TARGET_END ios $device $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ) > "$RUN/$device.log" 2>&1 &
  pids="$pids $!"
}

deploy_android 9885e6503930304946
deploy_android RF8M21J8XRT
deploy_android RF8M90QE7LX
deploy_ios AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A
deploy_ios 0A947DBD-A462-5BAA-AB84-17F143D41619

deploy_status=0
for pid in $pids; do
  wait "$pid" || deploy_status=1
done

echo "END_ALL=$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$RUN/batch.txt"
for file in "$RUN"/*.log "$RUN"/source-and-host.txt; do
  echo "==== $(basename "$file") ===="
  cat "$file"
done

exit "$deploy_status"
"""

    remote = run(["ssh", "mba13", "bash", "-s"], input=remote_script)
    copy = run(["scp", "-r", f"mba13:{remote_dir}/.", str(local_logs)])

    print(f"LOCAL_LOGS={local_logs}")
    for path in sorted(local_logs.glob("*")):
        print(path.relative_to(run_dir))

    return remote.returncode or copy.returncode


if __name__ == "__main__":
    raise SystemExit(main())
