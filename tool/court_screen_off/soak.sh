#!/bin/bash
# Screen-off soak for the court runtime on one rooted fleet phone (K1 key risk:
# does Camera2 keep recording with the screen off, locked and dozing?).
#
# usage: tool/court_screen_off/soak.sh ADB_ENDPOINT LABEL PORT [OFF_S] [ON_S] [APK]
#
# Runs on the Mac. Starts tool/court_mock_k2.dart on PORT (adb reverse), turns the
# screen off, enrolls the court app and starts it the way the boot path does (root
# `am start` of CourtActivity, screen off and locked). The mock records OFF_S + ON_S
# seconds. Phases, one sample every 10 s:
#   off      screen off, locked
#   off-doze same, with `dumpsys battery unplug` + `deviceidle force-idle` (deep doze)
#   on       screen forced on (`svc power stayon true` + WAKEUP), still locked
# Charging is cut (batt_slate_mode=1) while recording when the battery is at least
# SOAK_MIN_CUT_PCT (default 35) so current_now is the phone's real draw.
# A batt_slate_mode toggle wakes the display on Samsung (charger plug/unplug), so
# every toggle is followed by a SLEEP key.
# SOAK_SSH_HOST=<tailscale name> forwards PORT over the phone's Termux sshd instead of
# adb reverse. Everything is restored on exit. Report: tool/court_screen_off/report.py OUT.
# Take the fleet device lock (/tmp/court-fleet-locks/<serial>) before running.
set -uo pipefail
EP=$1 LABEL=$2 PORT=$3 OFF_S=${4:-600} ON_S=${5:-180} APK=${6:-}
PKG=com.amaia23.hydracam.court
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${SOAK_OUT:-/tmp/court-screen-off}/$LABEL-$(date +%Y%m%d-%H%M%S)
MIN_CUT=${SOAK_MIN_CUT_PCT:-35}
B=/sys/class/power_supply/battery
mkdir -p "$OUT"
echo "$OUT"

A() { timeout 60 adb -s "$EP" shell "$@" | tr -d '\r'; }
SU() { A "su -c '$1'"; } # $1 must not contain single quotes
log() { echo "$(date +%T) $*" | tee -a "$OUT/run.log"; }
phase() { echo "$1" > "$OUT/phase"; log "phase $1"; }

MOCK='' SAMPLER='' TUNNEL=''
restore() {
  log "restore"
  SU "svc power stayon false; settings put global stay_on_while_plugged_in 0; dumpsys deviceidle unforce; dumpsys battery reset; echo 0 > $B/batt_slate_mode; sleep 2; input keyevent 223" >> "$OUT/run.log" 2>&1
  adb -s "$EP" reverse --remove "tcp:$PORT" > "$OUT/reverse-remove.log" 2>&1
  [ -n "$TUNNEL" ] && kill "$TUNNEL" 2>> "$OUT/kill.log"
  [ -n "$SAMPLER" ] && kill "$SAMPLER" 2> "$OUT/kill.log"
  [ -n "$MOCK" ] && kill "$MOCK" 2>> "$OUT/kill.log"
  SU "cat $B/batt_slate_mode; dumpsys display | grep -o \"mScreenState=[A-Z_]*\" | head -1" | tee -a "$OUT/run.log"
}
trap restore EXIT

A 'getprop ro.product.model; getprop ro.build.version.release; getprop ro.serialno' | tee "$OUT/device.txt"
if [ -n "$APK" ]; then
  log "install $APK"
  timeout 900 adb -s "$EP" install -r -g "$APK" 2>&1 | tail -1 | tee -a "$OUT/run.log"
fi
A "dumpsys package $PKG | grep -m2 -E 'versionName|lastUpdateTime'" | tee -a "$OUT/run.log"
# The court runtime refuses to record without root (nack not_rooted). Grant su to its
# uid the way court-fleet/phone-setup/court-remote.sh grants Termux.
UID_=$(A "dumpsys package $PKG | grep -m1 -o 'userId=[0-9]*'" | cut -d= -f2)
[ -n "$UID_" ] || { log "FAIL: $PKG not installed"; exit 1; }
SU "magisk --sqlite \"INSERT OR REPLACE INTO policies (uid,policy,until,logging,notification) VALUES($UID_,2,0,1,0)\"" >> "$OUT/run.log"
log "magisk su granted to uid $UID_"
timeout 60 adb -s "$EP" push "$HERE/sample.sh" /data/local/tmp/court-soak-sample.sh > /dev/null || exit 1

phase prep
SU "am force-stop $PKG; input keyevent 223" >> "$OUT/run.log"
sleep 3
CAP=$(SU "cat $B/capacity")
CUT=0
if [ "${CAP:-0}" -ge "$MIN_CUT" ] && SU "test -e $B/batt_slate_mode"; then CUT=1; fi
log "battery $CAP% cut=$CUT"
(
  while :; do
    echo "$(date +%s) phase=$(cat "$OUT/phase") $(SU 'sh /data/local/tmp/court-soak-sample.sh')" >> "$OUT/samples.txt"
    sleep 10
  done
) &
SAMPLER=$!

(cd "$REPO" && exec timeout $((OFF_S + ON_S + 1500)) dart run tool/court_mock_k2.dart \
  --port "$PORT" --out "$OUT/mock" --idle-s 20 --record-s $((OFF_S + ON_S)) \
  --tiers proxy --no-signals --exit-after-s $((OFF_S + ON_S + 1200))) > "$OUT/mock.log" 2>&1 &
MOCK=$!
sleep 8
if [ -n "${SOAK_SSH_HOST:-}" ]; then
  # adb reverse fails on some adbd over TCP (S7, Android 8: "more than one
  # device/emulator"); forward the phone's loopback port over Termux sshd instead.
  ssh -N -o BatchMode=yes -o IdentityAgent=none -o IdentitiesOnly=yes \
    -i "${COURT_PHONE_KEY:-$HOME/.ssh/court_phones_ed25519}" -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=20 -p 8022 -R "$PORT:127.0.0.1:$PORT" "$SOAK_SSH_HOST" >> "$OUT/run.log" 2>&1 &
  TUNNEL=$!
  sleep 5
else
  timeout 30 adb -s "$EP" reverse "tcp:$PORT" "tcp:$PORT" >> "$OUT/run.log" 2>&1
fi
# Mock secret only; the mock accepts any non-empty secret.
SU "am broadcast -f 0x20 -n $PKG/$PKG.CourtEnrollReceiver -a $PKG.ENROLL --es k2Url http://127.0.0.1:$PORT --es deviceId soak-$LABEL --es secret soak --es courtId soak --es slot soak-$LABEL --ei mountRev 0" | tail -1 | tee -a "$OUT/run.log"
# The boot path: root `am start` of the activity, with the screen off and locked.
SU "am start -n $PKG/$PKG.CourtActivity" | tail -1 | tee -a "$OUT/run.log"
SU "dumpsys display | grep -o \"mScreenState=[A-Z_]*\" | head -1" | tee -a "$OUT/run.log"

for _ in $(seq 1 60); do
  grep -q '"recording.started"' "$OUT/mock/c1.jsonl" 2> /dev/null && break
  sleep 3
done
if ! grep -q '"recording.started"' "$OUT/mock/c1.jsonl" 2> /dev/null; then
  log "FAIL: no recording.started within 3 min"
  grep -o '"type":"[a-z._]*"' "$OUT/mock/c1.jsonl" 2> /dev/null | sort | uniq -c | tee -a "$OUT/run.log"
  exit 2
fi
[ "$CUT" = 1 ] && SU "echo 1 > $B/batt_slate_mode; sleep 2; input keyevent 223" >> "$OUT/run.log"
phase off
sleep $((OFF_S / 2))
phase off-doze
SU "dumpsys battery unplug; dumpsys deviceidle force-idle" | tee -a "$OUT/run.log"
sleep $((OFF_S - OFF_S / 2))
SU "dumpsys deviceidle unforce; dumpsys battery reset" >> "$OUT/run.log"
phase on
SU "svc power stayon true; input keyevent 224" >> "$OUT/run.log"
# stayon only holds while Android sees a charger, so keep poking WAKEUP too.
END=$(($(date +%s) + ON_S))
while [ "$(date +%s)" -lt "$END" ]; do
  sleep 5
  SU "input keyevent 224" >> "$OUT/run.log"
done
phase upload
SU "svc power stayon false; settings put global stay_on_while_plugged_in 0; echo 0 > $B/batt_slate_mode; sleep 2; input keyevent 223" >> "$OUT/run.log"
wait "$MOCK"
log "mock exited $?"
MOCK=''
python3 "$HERE/report.py" "$OUT" | tee "$OUT/report.md"
