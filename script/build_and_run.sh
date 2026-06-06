#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="HydraCam"
BUNDLE_ID="com.example.sportCamSync"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
APP_BUNDLE="$ROOT_DIR/build/macos/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

kill_existing() {
  local pids
  pids="$(pgrep -x "$APP_NAME" || true)"
  if [[ -n "$pids" ]]; then
    echo "Stopping existing $APP_NAME process(es): $pids"
    kill $pids
  fi
}

build_app() {
  "$FLUTTER_BIN" build macos --debug
}

open_app() {
  if /usr/bin/open -n "$APP_BUNDLE"; then
    return 0
  fi

  echo "open failed; starting $APP_NAME binary directly in background" >&2
  "$APP_BINARY" &
}

cd "$ROOT_DIR"
kill_existing

case "$MODE" in
  run)
    build_app
    open_app
    ;;
  --debug|debug)
    "$FLUTTER_BIN" run -d macos --debug
    ;;
  --logs|logs)
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    build_app
    open_app
    sleep 4
    pgrep -x "$APP_NAME"
    kill_existing
    ;;
  *)
    usage
    exit 2
    ;;
esac
