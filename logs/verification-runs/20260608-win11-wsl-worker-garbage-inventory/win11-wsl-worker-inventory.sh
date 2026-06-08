#!/usr/bin/env bash
set +e
export LC_ALL=C

section() {
  printf '\n### %s\n' "$1"
}

measure_path() {
  path="$1"
  if [ -e "$path" ]; then
    timeout 20s du -xsh "$path" 2>&1 || true
  else
    printf 'MISSING\t%s\n' "$path"
  fi
}

top_children() {
  path="$1"
  limit="${2:-30}"
  if [ -d "$path" ]; then
    timeout 40s sh -c "du -xhd1 \"$path\" 2>/dev/null | sort -hr | head -n $limit" || true
  else
    printf 'MISSING\t%s\n' "$path"
  fi
}

find_recent_large_files() {
  path="$1"
  if [ -d "$path" ]; then
    timeout 45s find "$path" -xdev -type f -size +100M \
      -printf '%s\t%TY-%Tm-%Td %TH:%TM\t%p\n' 2>/dev/null |
      sort -nr |
      head -n 80 || true
  else
    printf 'MISSING\t%s\n' "$path"
  fi
}

find_marker_paths() {
  root="$1"
  if [ -d "$root" ]; then
    timeout 45s find "$root" -xdev \
      \( -iname '*keob*' -o -iname '*worker*' -o -iname '*celery*' -o -iname '*rq*' -o -iname '*pm2*' -o -iname '*supervisor*' -o -iname '*hydra*' \) \
      -printf '%y\t%TY-%Tm-%Td %TH:%TM\t%p\n' 2>/dev/null |
      head -n 200 || true
  fi
}

section "identity"
printf 'date=%s\n' "$(date -Is 2>/dev/null || date)"
printf 'whoami=%s\n' "$(whoami 2>/dev/null)"
printf 'hostname=%s\n' "$(hostname 2>/dev/null)"
uname -a 2>/dev/null || true
cat /etc/os-release 2>/dev/null || true

section "mounts-and-filesystems"
df -hT -x tmpfs -x devtmpfs 2>/dev/null || df -h 2>/dev/null || true
mount | sed -n '1,80p' || true

section "users-and-homes"
getent passwd | awk -F: '$3 >= 1000 && $7 !~ /nologin|false/ { print $1 "\t" $3 "\t" $6 "\t" $7 }' || true
ls -la /home 2>/dev/null || true

section "candidate-root-sizes"
for path in \
  /var/tmp \
  /tmp \
  /var/log \
  /var/cache \
  /var/lib/docker \
  /var/lib/containerd \
  /var/lib/containers \
  /var/lib/snapd \
  /var/lib/apt/lists \
  /var/cache/apt \
  /var/crash \
  /opt \
  /srv \
  /root \
  /home
do
  measure_path "$path"
done

section "candidate-top-children"
for path in \
  /var/tmp \
  /tmp \
  /var/log \
  /var/cache \
  /var/lib \
  /opt \
  /srv \
  /root \
  /home
do
  printf '\n-- %s --\n' "$path"
  top_children "$path" 40
done

section "large-files"
for path in \
  /var/tmp \
  /tmp \
  /var/log \
  /var/cache \
  /var/lib \
  /root \
  /home \
  /opt \
  /srv
do
  printf '\n-- %s --\n' "$path"
  find_recent_large_files "$path"
done

section "worker-processes"
ps auxww 2>/dev/null |
  awk 'NR == 1 || tolower($0) ~ /keob|worker|celery|rq|pm2|supervisor|node|python|gunicorn|uvicorn|docker|containerd|hydracam|motherboard|mobo|codex/' || true

section "service-manager-hints"
systemctl list-units --type=service --all --no-pager 2>/dev/null |
  grep -Ei 'keob|worker|celery|rq|pm2|supervisor|docker|containerd|mobo|hydra|codex' || true
service --status-all 2>/dev/null |
  grep -Ei 'keob|worker|celery|rq|pm2|supervisor|docker|containerd|mobo|hydra|codex' || true

section "scheduled-work"
for user in root jose ubuntu; do
  printf '\n-- crontab %s --\n' "$user"
  crontab -u "$user" -l 2>/dev/null || true
done
ls -la /etc/cron.d /etc/systemd/system 2>/dev/null | sed -n '1,220p' || true

section "keob-worker-marker-paths"
for path in /var/tmp /tmp /var/log /var/lib /opt /srv /root /home; do
  printf '\n-- %s --\n' "$path"
  find_marker_paths "$path"
done

section "package-and-runtime-hints"
command -v docker >/dev/null 2>&1 && docker ps -a 2>/dev/null || true
command -v docker >/dev/null 2>&1 && docker images 2>/dev/null || true
command -v pm2 >/dev/null 2>&1 && pm2 list 2>/dev/null || true
command -v python3 >/dev/null 2>&1 && python3 --version 2>/dev/null || true
command -v node >/dev/null 2>&1 && node --version 2>/dev/null || true
command -v npm >/dev/null 2>&1 && npm --version 2>/dev/null || true
command -v pip >/dev/null 2>&1 && pip cache dir 2>/dev/null || true
command -v pip3 >/dev/null 2>&1 && pip3 cache dir 2>/dev/null || true

section "cleanup-candidate-notes"
printf 'Read-only inventory complete. No files were deleted or modified.\n'
