# shellcheck shell=sh
# Runs on the phone as root, once per sample: su -c sh /data/local/tmp/court-soak-sample.sh
# One line of key=value pairs. Also refreshes the charge-cap lease so court-boot.sh
# does not turn charging back on while the soak holds batt_slate_mode=1.
B=/sys/class/power_supply/battery
PKG=com.amaia23.hydracam.court
touch /data/local/tmp/charge-cap.lease
p=$(dumpsys power)
d=$(dumpsys display | grep -o 'mScreenState=[A-Z_]*' | head -1)
w=$(echo "$p" | grep -o 'mWakefulness=[A-Za-z]*' | head -1)
pid=$(pidof $PKG)
cam=$(dumpsys media.camera | grep -c "$PKG")
echo "cap=$(cat $B/capacity) ma=$(cat $B/current_now) uv=$(cat $B/voltage_now) temp=$(cat $B/temp) slate=$(cat $B/batt_slate_mode) display=${d##*=} wake=${w##*=} pid=${pid:-none} cam=$cam deep=$(dumpsys deviceidle get deep) bright=$(settings get system screen_brightness)"
