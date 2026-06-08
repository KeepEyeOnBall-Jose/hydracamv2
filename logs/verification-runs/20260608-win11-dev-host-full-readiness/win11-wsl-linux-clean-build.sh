#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/jose/development/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PUB_CACHE="/mnt/d/pub-cache"
export TMPDIR="/mnt/d/tmp-wsl"
mkdir -p "$PUB_CACHE" "$TMPDIR"

repo=/mnt/d/src/work/hydracamv2

section() {
  echo
  echo "=== $1 ==="
}

section context
date --iso-8601=seconds
hostname
whoami
echo "repo=$repo"
git -C "$repo" status -sb --untracked-files=no
df -h /
df -h /mnt/c /mnt/d || true

cd "$repo"

section "flutter clean"
/home/jose/development/flutter/bin/flutter clean

section "flutter pub get"
/home/jose/development/flutter/bin/flutter pub get

section "flutter build linux debug"
/home/jose/development/flutter/bin/flutter build linux --debug

section "linux binary smoke"
binary="$repo/build/linux/x64/debug/bundle/sport_cam_sync"
ls -lh "$binary"
echo "DISPLAY=${DISPLAY:-}"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
set +e
timeout 12s "$binary"
run_exit=$?
set -e
echo "binary_run_exit=$run_exit"

section done
