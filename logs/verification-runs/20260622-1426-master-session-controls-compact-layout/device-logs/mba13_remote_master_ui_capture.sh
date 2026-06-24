#!/usr/bin/env bash
set -euo pipefail

ADB="/Users/jose/Library/Android/sdk/platform-tools/adb"
APK="/Users/jose/src/work/hydracamv2-mba13-deploy/build/app/outputs/flutter-apk/app-debug-local-signed.apk"
OUT_DIR="/Users/jose/src/work/hydracamv2-mba13-deploy/master-ui-capture-20260622-1426"
PKG="com.amaia23.hydracam"
MAIN_ACTIVITY="${PKG}/.MainActivity"
SERIALS=("9885e6503930304946" "RF8M90QE7LX")
PORTS=("6711" "6712")

mkdir -p "${OUT_DIR}/screenshots" "${OUT_DIR}/video" "${OUT_DIR}/logs"

trap 'for serial in "${SERIALS[@]}"; do "${ADB}" -s "${serial}" logcat -d > "${OUT_DIR}/logs/logcat-${serial}.txt" 2>/dev/null || true; done' EXIT

"${ADB}" devices -l | tee "${OUT_DIR}/logs/adb-devices-before.txt"

for serial in "${SERIALS[@]}"; do
  "${ADB}" -s "${serial}" shell getprop ro.product.model \
    | tr -d "\r" > "${OUT_DIR}/logs/model-${serial}.txt"
  "${ADB}" -s "${serial}" shell getprop ro.build.version.release \
    | tr -d "\r" > "${OUT_DIR}/logs/android-version-${serial}.txt"
  "${ADB}" -s "${serial}" install -r "${APK}" \
    | tee "${OUT_DIR}/logs/install-${serial}.txt"
  for permission in \
    CAMERA \
    RECORD_AUDIO \
    ACCESS_FINE_LOCATION \
    ACCESS_COARSE_LOCATION \
    READ_EXTERNAL_STORAGE \
    READ_MEDIA_IMAGES \
    READ_MEDIA_VIDEO; do
    "${ADB}" -s "${serial}" shell pm grant \
      "${PKG}" "android.permission.${permission}" || true
  done
done

for index in "${!SERIALS[@]}"; do
  serial="${SERIALS[$index]}"
  port="${PORTS[$index]}"

  "${ADB}" -s "${serial}" logcat -c || true
  "${ADB}" -s "${serial}" shell input keyevent WAKEUP || true
  "${ADB}" -s "${serial}" shell wm dismiss-keyguard || true
  "${ADB}" -s "${serial}" shell am force-stop "${PKG}" || true
  "${ADB}" -s "${serial}" forward --remove "tcp:${port}" || true
  "${ADB}" -s "${serial}" forward "tcp:${port}" tcp:4762

  "${ADB}" -s "${serial}" shell am start \
    -n "${MAIN_ACTIVITY}" \
    --es role master \
    --es automationTargetId "${serial}" \
    | tee "${OUT_DIR}/logs/launch-master-${serial}.txt"

  health_json="${OUT_DIR}/logs/health-${serial}.json"
  bridge_ready=0
  for attempt in $(seq 1 45); do
    if curl -fsS "http://127.0.0.1:${port}/healthz" > "${health_json}" &&
      python3 - "${health_json}" "${serial}" <<'PY' >/dev/null 2>&1
import json
import sys

health_path = sys.argv[1]
expected = sys.argv[2]
with open(health_path, "r", encoding="utf-8") as handle:
    health = json.load(handle)
if health.get("automationTargetId") != expected:
    raise SystemExit(1)
commands = set(health.get("commands", []))
if "capture_screenshot" not in commands:
    raise SystemExit(1)
PY
    then
      bridge_ready=1
      break
    fi
    sleep 1
  done

  if [[ "${bridge_ready}" != "1" ]]; then
    echo "Automation bridge did not expose capture_screenshot for ${serial}" >&2
    cat "${health_json}" >&2 || true
    exit 1
  fi

  python3 - "${health_json}" "${serial}" <<'PY'
import json
import sys

health_path = sys.argv[1]
expected = sys.argv[2]
with open(health_path, "r", encoding="utf-8") as handle:
    health = json.load(handle)
if health.get("automationTargetId") != expected:
    raise SystemExit(
        f"Bridge target mismatch: {health.get('automationTargetId')} != {expected}"
    )
commands = set(health.get("commands", []))
if "capture_screenshot" not in commands:
    raise SystemExit("Bridge does not expose capture_screenshot")
PY

  screenshot_response="${OUT_DIR}/logs/capture-response-${serial}.json"
  curl -fsS \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"master-compact-${serial}\",\"pixelRatio\":1.0}" \
    "http://127.0.0.1:${port}/commands/capture_screenshot" \
    > "${screenshot_response}"

  screenshot_path="$(
    python3 - "${screenshot_response}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    response = json.load(handle)
print(response["result"]["filePath"])
PY
  )"
  "${ADB}" -s "${serial}" exec-out run-as "${PKG}" cat "${screenshot_path}" \
    > "${OUT_DIR}/screenshots/master-compact-${serial}.png"
  "${ADB}" -s "${serial}" shell screencap -p \
    > "${OUT_DIR}/screenshots/system-master-compact-${serial}.png"

  remote_video="/sdcard/hydracam-master-compact-${serial}.mp4"
  "${ADB}" -s "${serial}" shell rm -f "${remote_video}" || true
  "${ADB}" -s "${serial}" shell screenrecord --time-limit 3 "${remote_video}" \
    | tee "${OUT_DIR}/logs/screenrecord-${serial}.txt" || true
  "${ADB}" -s "${serial}" pull "${remote_video}" \
    "${OUT_DIR}/video/master-compact-${serial}.mp4" || true

  "${ADB}" -s "${serial}" logcat -d > "${OUT_DIR}/logs/logcat-${serial}.txt"
  if grep -E "RenderFlex overflowed|BOTTOM OVERFLOWED|RIGHT OVERFLOWED" \
    "${OUT_DIR}/logs/logcat-${serial}.txt"; then
    echo "Flutter overflow marker found for ${serial}" >&2
    exit 1
  fi
done

find "${OUT_DIR}" -type f | sort
