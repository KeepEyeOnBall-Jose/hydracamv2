# Runs on the phone as root (fleet_run.py): one sample of CPU, app CPU, thermal zones, battery.
head -1 /proc/stat
p=$(pidof "$1")
echo pid=$p
[ -n "$p" ] && cut -d' ' -f14,15 /proc/$p/stat
for z in /sys/class/thermal/thermal_zone*; do echo zone $(cat $z/type)=$(cat $z/temp); done
echo battery=$(cat /sys/class/power_supply/battery/temp)
dumpsys thermalservice 2>/dev/null | grep -m1 'Thermal Status'
