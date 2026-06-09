#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-all}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
AAB_PATH="$ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"
IPA_DIR="$ROOT_DIR/build/ios/ipa"
IPA_PATH="$IPA_DIR/HydraCam.ipa"
STORE_METADATA_FORMAT="HydraCamStoreArtifactMetadataV1"

build_flags=()
if [[ -n "${BUILD_NAME:-}" ]]; then
  build_flags+=(--build-name "$BUILD_NAME")
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  build_flags+=(--build-number "$BUILD_NUMBER")
fi
if [[ -n "${HYDRACAM_PRIVACY_POLICY_URL:-}" ]]; then
  build_flags+=(
    --dart-define
    "HYDRACAM_PRIVACY_POLICY_URL=$HYDRACAM_PRIVACY_POLICY_URL"
  )
fi
if [[ -n "${HYDRACAM_SUPPORT_URL:-}" ]]; then
  build_flags+=(
    --dart-define
    "HYDRACAM_SUPPORT_URL=$HYDRACAM_SUPPORT_URL"
  )
fi
if [[ -n "${HYDRACAM_ACCOUNT_DELETION_URL:-}" ]]; then
  build_flags+=(
    --dart-define
    "HYDRACAM_ACCOUNT_DELETION_URL=$HYDRACAM_ACCOUNT_DELETION_URL"
  )
fi

run_checks() {
  "$FLUTTER_BIN" pub get
  "$FLUTTER_BIN" analyze
  "$FLUTTER_BIN" test
}

write_store_metadata() {
  local artifact_path="$1"
  local platform="$2"
  local builder="$3"
  local metadata_path="${artifact_path}.store-metadata.tsv"
  local artifact_hash

  if [[ ! -s "$artifact_path" ]]; then
    echo "Expected artifact missing or empty: $artifact_path" >&2
    exit 1
  fi

  artifact_hash="$(shasum -a 256 "$artifact_path" | awk '{print $1}')"
  {
    printf 'format\t%s\n' "$STORE_METADATA_FORMAT"
    printf 'platform\t%s\n' "$platform"
    printf 'artifact_path\t%s\n' "$artifact_path"
    printf 'artifact_sha256\t%s\n' "$artifact_hash"
    printf 'builder\t%s\n' "$builder"
    printf 'built_at_utc\t%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf 'build_name\t%s\n' "${BUILD_NAME:-}"
    printf 'build_number\t%s\n' "${BUILD_NUMBER:-}"
    printf 'hydracam_privacy_policy_url\t%s\n' "${HYDRACAM_PRIVACY_POLICY_URL:-}"
    printf 'hydracam_support_url\t%s\n' "${HYDRACAM_SUPPORT_URL:-}"
    printf 'hydracam_account_deletion_url\t%s\n' "${HYDRACAM_ACCOUNT_DELETION_URL:-}"
  } > "$metadata_path"

  echo "Wrote store metadata: $metadata_path"
}

build_android() {
  rm -f "$AAB_PATH" "${AAB_PATH}.store-metadata.tsv"
  if [[ ${#build_flags[@]} -eq 0 ]]; then
    "$FLUTTER_BIN" build appbundle --release
  else
    "$FLUTTER_BIN" build appbundle --release "${build_flags[@]}"
  fi
  write_store_metadata "$AAB_PATH" android "scripts/build_store_artifacts.sh"
}

build_ios() {
  rm -f "$IPA_DIR"/*.ipa "$IPA_DIR"/*.ipa.store-metadata.tsv
  if [[ ${#build_flags[@]} -eq 0 ]]; then
    "$FLUTTER_BIN" build ipa --release --export-method app-store
  else
    "$FLUTTER_BIN" build ipa --release --export-method app-store "${build_flags[@]}"
  fi
  write_store_metadata "$IPA_PATH" ios "scripts/build_store_artifacts.sh"
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
