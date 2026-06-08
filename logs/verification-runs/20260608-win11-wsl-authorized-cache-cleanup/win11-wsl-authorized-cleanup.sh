#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

log() {
  printf '\n### %s\n' "$1"
}

size_or_missing() {
  path="$1"
  if [ -e "$path" ]; then
    du -xsh "$path" 2>/dev/null || true
  else
    printf 'MISSING\t%s\n' "$path"
  fi
}

if ! grep -q '^VERSION_ID="22.04"$' /etc/os-release; then
  echo "Refusing to run: this is not Ubuntu 22.04" >&2
  cat /etc/os-release >&2 || true
  exit 10
fi

targets=(
  "/home/jose/borrame"
  "/home/jose/.cache/pip"
  "/home/jose/.local/share/mamba/pkgs/cache"
)

protected="/home/jose/keob-nodes"

log "identity"
date -Is
hostname
whoami
cat /etc/os-release

log "process-precheck"
ps auxww |
  awk 'NR == 1 || tolower($0) ~ /pip|mamba|conda|keob|queue-poller|python|node|worker/' || true

log "df-before"
df -hT / /home /tmp 2>/dev/null || df -h / /home /tmp

log "sizes-before"
for path in "${targets[@]}" "$protected"; do
  size_or_missing "$path"
done

log "delete-authorized-targets"
for path in "${targets[@]}"; do
  case "$path" in
    /home/jose/borrame|/home/jose/.cache/pip|/home/jose/.local/share/mamba/pkgs/cache)
      if [ -e "$path" ]; then
        printf 'deleting\t%s\n' "$path"
        rm -rf -- "$path"
      else
        printf 'already-missing\t%s\n' "$path"
      fi
      ;;
    *)
      echo "Refusing unexpected target: $path" >&2
      exit 11
      ;;
  esac
done

mkdir -p /home/jose/.cache /home/jose/.local/share/mamba/pkgs
chown -R jose:jose /home/jose/.cache /home/jose/.local/share/mamba 2>/dev/null || true

log "sizes-after"
for path in "${targets[@]}" "$protected"; do
  size_or_missing "$path"
done

log "df-after"
df -hT / /home /tmp 2>/dev/null || df -h / /home /tmp

log "keob-nodes-integrity"
if [ -d "$protected" ]; then
  printf 'PRESENT\t%s\n' "$protected"
  du -xsh "$protected" 2>/dev/null || true
  find "$protected" -maxdepth 2 -type d \( -name credentials -o -name .git -o -name queue-poller \) -print 2>/dev/null | sort
else
  printf 'MISSING\t%s\n' "$protected"
  exit 12
fi

log "done"
printf 'Authorized cleanup complete. No keob-nodes deletion performed.\n'
