#!/usr/bin/env bash
set +e
export LC_ALL=C

section() {
  printf '\n### %s\n' "$1"
}

top_children() {
  path="$1"
  if [ -d "$path" ]; then
    printf '\n-- %s --\n' "$path"
    timeout 45s du -xhd1 "$path" 2>/dev/null | sort -hr | head -n 80 || true
  fi
}

large_files() {
  path="$1"
  if [ -d "$path" ]; then
    printf '\n-- %s --\n' "$path"
    timeout 45s find "$path" -xdev -type f -size +50M \
      -printf '%s\t%TY-%Tm-%Td %TH:%TM\t%p\n' 2>/dev/null |
      sort -nr |
      head -n 80 || true
  fi
}

section "home-top-children"
for path in /home/* /root /opt /srv; do
  top_children "$path"
done

section "keob-path-sizes"
for path in \
  /home/ubuntu/bin/keob-nodes \
  /home/ubuntu/venv \
  /home/ubuntu/.cache \
  /home/vectorblanco/.cache \
  /home/vectorblanco/.vscode-server \
  /home/vectorblanco/.cursor-server \
  /home/vectorblanco/pycharm \
  /home/jose/keob-nodes \
  /home/jose/keob-modeller \
  /home/jose/.cache \
  /home/jose/.local/share/mamba \
  /home/jose/.vscode-server \
  /home/jose/borrame \
  /home/jose/development/flutter \
  /opt/bin/keob-modeller \
  /opt/pycharm-2024.3.1.1
do
  if [ -e "$path" ]; then
    timeout 30s du -xsh "$path" 2>/dev/null || true
  fi
done

section "large-home-files"
for path in /home/* /root /opt /srv; do
  large_files "$path"
done

section "crontabs"
for user in root jose ubuntu vectorblanco; do
  printf '\n-- %s --\n' "$user"
  crontab -u "$user" -l 2>/dev/null || true
done
