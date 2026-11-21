#!/system/bin/sh
# Court phones: enable adb over Wi-Fi on 5555 and SSH on 8022 after every boot,
# and hold battery near 60%. Runs from Magisk service.d before first unlock.
# Nothing on the path to adb and SSH may depend on credential-encrypted
# storage (/data/data, /sdcard) until the device is unlocked.
# COURT_TEST_ROOT and COURT_BOOT_ONCE exist for local verification only.
R=${COURT_TEST_ROOT:-}
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
setprop service.adb.tcp.port 5555
# persist: adbd falls back to it when service.adb.tcp.port is unset, so an
# unrooted boot still listens on 5555 and `adb reboot recovery` restores root.
[ "$(getprop persist.adb.tcp.port)" = 5555 ] || setprop persist.adb.tcp.port 5555
stop adbd; start adbd
P=$R/sys/class/power_supply/battery
# store_mode=1: kernel holds 60-70% on supported Samsung models (except S7).
echo 1 > "$P/store_mode"
# 60% cap on opted-in phones (/data/adb/charge-cap.on).
# S10e/S20 FE use batt_full_capacity; S7/S9 use charge-cap.sh (batt_slate_mode).
[ -f "$R/data/adb/charge-cap.on" ] && [ -e "$P/batt_full_capacity" ] && echo 60 > "$P/batt_full_capacity"
settings put global stay_on_while_plugged_in 0
settings put global wifi_sleep_policy 2
settings put global package_verifier_enable 0
# Keep Termux out of the app-standby firewall (fw_standby drops idle app uids).
dumpsys deviceidle whitelist +com.termux
# SSH on 8022: Termux's own sshd once credential-encrypted storage unlocks, or
# root sshd snapshot in /data/adb/court-ssh before first unlock.
S=$R/data/adb/court-ssh
T=$R/data/data/com.termux
termux_sshd() {
  U=$(stat -c %u "$T")
  case "$U" in ''|*[!0-9]*) echo 'Termux UID unavailable'; return 1;; esac
  [ "$U" -ge 10000 ] || { echo 'Refusing non-app Termux UID'; return 1; }
  pgrep -u "$U" -x sshd >/dev/null && return 0
  for p in $(pgrep -f "$S/bin/sshd"); do kill "$p"; sleep 1; done
  su -g "$U" -G 3003 -G 9997 "$U" -c 'export PREFIX=/data/data/com.termux/files/usr HOME=/data/data/com.termux/files/home PATH=/data/data/com.termux/files/usr/bin LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib; sshd'
  pgrep -u "$U" -x sshd >/dev/null
}
root_sshd() {
  [ -x "$S/bin/sshd" ] || return 0
  pgrep -f "$S/bin/sshd" >/dev/null || LD_LIBRARY_PATH="$S/lib" "$S/bin/sshd" -f "$S/sshd_config" -E "$S/sshd.log"
}
while true; do
  am set-standby-bucket com.termux active
  if [ -x "$T/files/usr/bin/sshd" ]; then termux_sshd || root_sshd; else root_sshd; fi
  [ "$(getprop service.adb.tcp.port)" = 5555 ] || { setprop service.adb.tcp.port 5555; stop adbd; start adbd; }
  # cmd, not svc: Magisk busybox has its own svc applet that shadows Android's.
  ip -4 addr show wlan0 2>/dev/null | grep -q inet || cmd wifi start-scan >/dev/null 2>&1
  # charge-cap.sh fail-safe: turn charging back on when its lease is 5 min stale.
  if [ "$(cat "$P/batt_slate_mode" 2>/dev/null)" = 1 ]; then
    L=$(stat -c %Y "$R/data/local/tmp/charge-cap.lease" 2>/dev/null || echo 0)
    [ $(($(date +%s) - L)) -lt 300 ] || echo 0 > "$P/batt_slate_mode"
  fi
  [ -n "${COURT_BOOT_ONCE:-}" ] && exit 0
  sleep 30
done
