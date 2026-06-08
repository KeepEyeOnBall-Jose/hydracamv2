#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/jose/development/flutter/bin:$PATH"
export PUB_CACHE="/mnt/d/pub-cache"
export TMPDIR="/mnt/d/tmp-wsl"
mkdir -p "$PUB_CACHE" "$TMPDIR"

if [[ -d /mnt/d/src/work/hydracamv2 ]]; then
  repo=/mnt/d/src/work/hydracamv2
elif [[ -d /mnt/c/Users/jose/src/work/hydracamv2 ]]; then
  repo=/mnt/c/Users/jose/src/work/hydracamv2
else
  echo "BLOCKER: HydraCam checkout missing in WSL mount paths"
  exit 1
fi

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
git -C "$repo" rev-parse HEAD
df -h /
df -h /mnt/c /mnt/d || true

section "flutter doctor"
/home/jose/development/flutter/bin/flutter doctor -v

section "enable linux desktop"
/home/jose/development/flutter/bin/flutter config --enable-linux-desktop

section "flutter pub get"
cd "$repo"
/home/jose/development/flutter/bin/flutter pub get

section "flutter build linux debug"
/home/jose/development/flutter/bin/flutter build linux --debug

section "linux binary"
binary="$repo/build/linux/x64/debug/bundle/sport_cam_sync"
if [[ -x "$binary" ]]; then
  ls -lh "$binary"
  ldd "$binary" || true
  echo "DISPLAY=${DISPLAY:-}"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
  set +e
  timeout 12s "$binary"
  run_exit=$?
  set -e
  echo "binary_run_exit=$run_exit"
else
  echo "binary=missing"
  exit 1
fi

section done
