#!/usr/bin/env bash
set +e
export LC_ALL=C

for path in \
  /home/jose/borrame \
  /home/jose/.cache \
  /home/jose/keob-nodes \
  /home/jose/.local/share/mamba
do
  printf '\n### %s\n' "$path"
  du -xsh "$path" 2>/dev/null || true

  printf '%s\n' '-- top children --'
  du -xhd1 "$path" 2>/dev/null | sort -hr | head -n 40 || true

  printf '%s\n' '-- second-level children --'
  find "$path" -xdev -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null |
    while IFS= read -r -d '' child; do
      du -xsh "$child" 2>/dev/null
    done |
    sort -hr |
    head -n 60 || true

  printf '%s\n' '-- large files >50M --'
  find "$path" -xdev -type f -size +50M \
    -printf '%s\t%TY-%Tm-%Td %TH:%TM\t%p\n' 2>/dev/null |
    sort -nr |
    head -n 60 || true
done

printf '\n### process check\n'
ps auxww 2>/dev/null |
  awk 'NR == 1 || tolower($0) ~ /pip|mamba|conda|keob|queue-poller|python|node|worker/'
