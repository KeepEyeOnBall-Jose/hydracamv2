#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-all}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

build_flags=()
if [[ -n "${BUILD_NAME:-}" ]]; then
  build_flags+=(--build-name "$BUILD_NAME")
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  build_flags+=(--build-number "$BUILD_NUMBER")
fi

run_checks() {
  "$FLUTTER_BIN" pub get
  "$FLUTTER_BIN" analyze
  "$FLUTTER_BIN" test
}

build_android() {
  "$FLUTTER_BIN" build appbundle --release "${build_flags[@]}"
}

build_ios() {
  "$FLUTTER_BIN" build ipa --release --export-method app-store "${build_flags[@]}"
}

cd "$ROOT_DIR"

if [[ "${SKIP_CHECKS:-0}" != "1" ]]; then
  run_checks
fi

case "$TARGET" in
  android)
    build_android
    ;;
  ios)
    build_ios
    ;;
  all)
    build_android
    build_ios
    ;;
  *)
    echo "Usage: $0 [android|ios|all]"
    exit 64
    ;;
esac
