#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-/mnt/d/src/work/hydracamv2}"
OUT_DIR="${OUT_DIR:-/mnt/d/hydracam-evidence/win11-triple-platform-camera-master-slave/linux-mock-media}"
MOCK_DIR="${MOCK_DIR:-/mnt/d/hydracam-evidence/win11-triple-platform-camera-master-slave/fallback-media}"
FLUTTER="${FLUTTER:-/home/jose/flutter-linux/bin/flutter}"
PORT="${PORT:-6500}"
TARGET_ID="${TARGET_ID:-linux-native}"
COURT_GUID="${COURT_GUID:-a2387237-cb34-428a-81cd-49a4563d2768}"

mkdir -p "$OUT_DIR/media"
cd "$REPO"

"$FLUTTER" pub get 2>&1 | tee "$OUT_DIR/pub-get.txt"

"$FLUTTER" run -d linux \
  --dart-define=HYDRACAM_AUTOMATION=true \
  --dart-define=HYDRACAM_AUTOMATION_ROLE=master \
  --dart-define=HYDRACAM_MOCK_CAMERA=true \
  --dart-define=HYDRACAM_MOCK_MEDIA_SOURCE_DIR="$MOCK_DIR" \
  --dart-define=HYDRACAM_AUTOMATION_TARGET_ID="$TARGET_ID" \
  --dart-define=HYDRACAM_AUTOMATION_PORT="$PORT" \
  >"$OUT_DIR/flutter-run.stdout.txt" \
  2>"$OUT_DIR/flutter-run.stderr.txt" &
APP_PID=$!

cleanup() {
  if kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

bridge_get() {
  curl -fsS --max-time "${3:-10}" "http://127.0.0.1:$PORT$1" -o "$2"
}

bridge_post() {
  curl -fsS --max-time "${4:-30}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$3" \
    "http://127.0.0.1:$PORT$1" \
    -o "$2"
}

for _ in $(seq 1 180); do
  if bridge_get "/healthz" "$OUT_DIR/health.json" 3; then
    python3 - "$OUT_DIR/health.json" "$TARGET_ID" <<'PY' && break || true
import json
import sys

health = json.load(open(sys.argv[1], encoding="utf-8"))
if health.get("status") == "ok" and health.get("automationTargetId") == sys.argv[2]:
    sys.exit(0)
sys.exit(1)
PY
  fi
  sleep 1
done

bridge_get "/healthz" "$OUT_DIR/health.json" 10
bridge_post "/settings" "$OUT_DIR/settings.json" '{"masterShouldRecord":true,"timerDuration":0,"autoplayVideoOnMaster":false,"flashForVideoAnnounce":false,"autoUploadMaterials":true,"deleteLocalAfterUpload":false,"cameraLensPreference":"autoBack","videoCaptureProfile":"dataSaver480p30"}' 30

SESSION_ID="codex-linux-mock-$(date +%Y%m%d-%H%M%S)"
if ! bridge_post "/commands/start_session" "$OUT_DIR/start-session.json" "{\"sessionId\":\"$SESSION_ID\",\"courtGuid\":\"$COURT_GUID\"}" 90; then
  bridge_post "/commands/start_local_session" "$OUT_DIR/start-local-session-fallback.json" "{\"sessionId\":\"$SESSION_ID-local\"}" 30
fi

bridge_post "/commands/take_photo" "$OUT_DIR/take-photo.json" '{"showCountdown":false}' 60
bridge_post "/commands/start_recording" "$OUT_DIR/start-recording.json" '{}' 60
sleep 4
bridge_post "/commands/stop_recording" "$OUT_DIR/stop-recording.json" '{}' 90

UPLOAD_STATUS="timeout"
for _ in $(seq 1 90); do
  bridge_get "/session" "$OUT_DIR/session-upload.json" 10
  bridge_get "/logs" "$OUT_DIR/logs.json" 20
  if python3 - "$OUT_DIR/session-upload.json" "$OUT_DIR/logs.json" <<'PY'
import json
import sys

session = json.load(open(sys.argv[1], encoding="utf-8"))
logs = json.load(open(sys.argv[2], encoding="utf-8"))
lines = list(logs.get("persistedLogLines") or [])
lines += [entry.get("message", "") for entry in logs.get("logs", [])]
uploaded = [line for line in lines if "Media uploaded:" in line or "Media uploaded successfully" in line]
failed = [line for line in lines if "Failed to upload media:" in line or "Error uploading media:" in line]
if failed:
    sys.exit(2)
if len(uploaded) >= 2 and not session.get("isUploading") and int(session.get("queueLength") or 0) == 0:
    sys.exit(0)
sys.exit(1)
PY
  then
    UPLOAD_STATUS="passed"
    break
  else
    code=$?
    if [ "$code" -eq 2 ]; then
      UPLOAD_STATUS="failed"
      break
    fi
  fi
  sleep 2
done

bridge_get "/logs" "$OUT_DIR/logs.json" 20
python3 - "$OUT_DIR/logs.json" "$OUT_DIR/media" "$OUT_DIR/summary.json" "$UPLOAD_STATUS" <<'PY'
import json
import re
import shutil
import sys
from pathlib import Path

logs_path = Path(sys.argv[1])
media_dir = Path(sys.argv[2])
summary_path = Path(sys.argv[3])
upload_status = sys.argv[4]
logs = json.loads(logs_path.read_text(encoding="utf-8"))
lines = list(logs.get("persistedLogLines") or [])
lines += [entry.get("message", "") for entry in logs.get("logs", [])]

def find_path(pattern):
    for line in lines:
        match = re.search(pattern, line)
        if match:
            return match.group(1).strip()
    return None

photo = find_path(r"(?:Mock photo saved|Photo saved) to session path:\s*(.+?\.jpg)\b")
video = find_path(r"(?:Mock video saved|Video saved) to session path:\s*(.+?\.mp4)\b")
copied = {}
for label, source_path in {"photo": photo, "video": video}.items():
    if source_path:
        source = Path(source_path)
        if source.exists():
            destination = media_dir / source.name
            shutil.copy2(source, destination)
            copied[label] = str(destination)

uploaded = [line for line in lines if "Media uploaded:" in line or "Media uploaded successfully" in line]
failed = [line for line in lines if "Failed to upload media:" in line or "Error uploading media:" in line]
summary = {
    "status": "passed" if upload_status == "passed" and photo and video and copied.get("photo") and copied.get("video") else "failed",
    "platform": "linux",
    "targetId": "linux-native",
    "captureMode": "mock-media-source",
    "photoPath": photo,
    "videoPath": video,
    "copiedPhoto": copied.get("photo"),
    "copiedVideo": copied.get("video"),
    "uploadedLineCount": len(uploaded),
    "failedUploadLineCount": len(failed),
    "uploadStatus": upload_status,
    "failedUploadLines": failed,
}
summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print(json.dumps(summary, indent=2))
PY

bridge_post "/commands/end_session" "$OUT_DIR/end-session.json" '{}' 30 || true
