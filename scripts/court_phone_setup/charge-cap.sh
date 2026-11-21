#!/system/bin/sh
# Court phones without a kernel charge cap (S7, S9): hold battery at 55-60%
# by toggling batt_slate_mode (1 = charger input off). Runs only when
# /data/adb/charge-cap.on exists. Every exit path leaves charging ON.
# Install as /data/adb/service.d/charge-cap.sh (mode 755).
N=${CHARGE_CAP_SYSFS:-/sys/class/power_supply/battery}
CAP=${CAP:-60}
RESUME=${RESUME:-55}
FLOOR=${FLOOR:-40}
LOG=${CHARGE_CAP_LOG:-/data/local/tmp/charge-cap.log}
LEASE=${CHARGE_CAP_LEASE:-/data/local/tmp/charge-cap.lease}
MARKER=${CHARGE_CAP_MARKER:-/data/adb/charge-cap.on}
TICK=${CHARGE_CAP_TICK:-60}
RESTART=${CHARGE_CAP_RESTART:-30}
on() { echo 0 > "$N/batt_slate_mode"; }
off() { echo 1 > "$N/batt_slate_mode"; }
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

if [ "${1:-}" = worker ]; then
  SUP=$2
  trap 'on; exit 0' TERM INT HUP
  while kill -0 "$SUP" 2>/dev/null; do
    L=$(cat "$N/capacity")
    S=$(cat "$N/batt_slate_mode")
    case "$L" in
      ''|*[!0-9]*) [ "$S" = 0 ] || log "capacity unreadable: charging ON"; on ;;
      *)
        if [ "$L" -le "$FLOOR" ]; then
          [ "$S" = 0 ] || log "level $L <= $FLOOR: charging ON (fail-safe)"
          on
        elif [ "$L" -ge "$CAP" ]; then
          [ "$S" = 1 ] || { log "level $L >= $CAP: charging OFF"; off; }
        elif [ "$L" -le "$RESUME" ]; then
          [ "$S" = 0 ] || { log "level $L <= $RESUME: charging ON"; on; }
        fi
        ;;
    esac
    touch "$LEASE"
    sleep "$TICK"
  done
  on
  log "supervisor $SUP gone: charging ON, worker exits"
  exit 0
fi

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 5; done
[ -f "$MARKER" ] || exit 0
[ -e "$N/batt_full_capacity" ] && { log "kernel cap (court-boot.sh): daemon not needed"; exit 0; }
[ -e "$N/batt_slate_mode" ] || { log "no batt_slate_mode: nothing to do"; exit 0; }
trap 'on; log "supervisor stopped: charging ON"; exit 0' TERM INT HUP
on
log "start: cap $CAP %, resume $RESUME %, floor $FLOOR %"
while true; do
  sh "$0" worker $$ &
  wait $!
  on
  log "worker exited: charging ON, restarting in $RESTART s"
  sleep "$RESTART"
done
