#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="logs/verification-runs/20260622-1426-master-session-controls-compact-layout"
REMOTE="jose@joss-macbook-air.tail6ce139.ts.net"
REMOTE_ROOT="/Users/jose/src/work/hydracamv2-mba13-deploy"
REMOTE_APK="${REMOTE_ROOT}/build/app/outputs/flutter-apk/app-debug-local-signed.apk"
REMOTE_SCRIPT="${REMOTE_ROOT}/master-ui-capture-20260622-1426.sh"
REMOTE_OUT="${REMOTE_ROOT}/master-ui-capture-20260622-1426"
SSH_OPTS=(
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o BatchMode=no
  -o ConnectTimeout=20
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=12
  -o StrictHostKeyChecking=accept-new
)
RSYNC_RSH="sshpass -f tempass.txt ssh ${SSH_OPTS[*]}"

mkdir -p \
  "${RUN_DIR}/screenshots" \
  "${RUN_DIR}/video" \
  "${RUN_DIR}/device-logs/mba13"

sshpass -f tempass.txt ssh "${SSH_OPTS[@]}" "${REMOTE}" \
  "mkdir -p '${REMOTE_ROOT}/build/app/outputs/flutter-apk'"

local_apk_sha="$(
  shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk \
    | awk '{print $1}'
)"
remote_apk_sha="$(
  sshpass -f tempass.txt ssh "${SSH_OPTS[@]}" "${REMOTE}" \
    "if [ -f '${REMOTE_APK}' ]; then shasum -a 256 '${REMOTE_APK}' | cut -d ' ' -f 1; fi" \
    | tr -d "\r"
)"
if [[ "${remote_apk_sha}" != "${local_apk_sha}" ]]; then
  rsync -az --checksum \
    -e "${RSYNC_RSH}" \
    build/app/outputs/flutter-apk/app-debug.apk \
    "${REMOTE}:${REMOTE_APK}"
else
  echo "Remote APK already matches local sha256: ${local_apk_sha}"
fi

rsync -az \
  -e "${RSYNC_RSH}" \
  "${RUN_DIR}/device-logs/mba13_remote_master_ui_capture.sh" \
  "${REMOTE}:${REMOTE_SCRIPT}"

set +e
sshpass -f tempass.txt ssh "${SSH_OPTS[@]}" "${REMOTE}" \
  "chmod +x '${REMOTE_SCRIPT}' && '${REMOTE_SCRIPT}'"
remote_status=$?
set -e

rsync -az \
  -e "${RSYNC_RSH}" \
  "${REMOTE}:${REMOTE_OUT}/screenshots/" \
  "${RUN_DIR}/screenshots/" || true

rsync -az \
  -e "${RSYNC_RSH}" \
  "${REMOTE}:${REMOTE_OUT}/logs/" \
  "${RUN_DIR}/device-logs/mba13/" || true

rsync -az \
  -e "${RSYNC_RSH}" \
  "${REMOTE}:${REMOTE_OUT}/video/" \
  "${RUN_DIR}/video/" || true

find "${RUN_DIR}/screenshots" "${RUN_DIR}/video" "${RUN_DIR}/device-logs/mba13" \
  -type f | sort

exit "${remote_status}"
