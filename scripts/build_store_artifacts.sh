#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-all}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
AAB_PATH="$ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"
IPA_DIR="$ROOT_DIR/build/ios/ipa"
IPA_PATH="$IPA_DIR/HydraCam.ipa"
IOS_ARCHIVE_PATH="$ROOT_DIR/build/ios/archive/Runner.xcarchive"
IOS_EXPORT_OPTIONS_PLIST="$IPA_DIR/ExportOptions.plist"
STORE_METADATA_FORMAT="HydraCamStoreArtifactMetadataV1"
ASC_AUTH_TEMP_FILES=()

cleanup_asc_auth_temp_files() {
  local temp_file

  for temp_file in "${ASC_AUTH_TEMP_FILES[@]:-}"; do
    [[ -n "$temp_file" ]] || continue
    rm -f "$temp_file"
  done
}

trap cleanup_asc_auth_temp_files EXIT

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

asc_env_value() {
  local value

  for value in "$@"; do
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

prepare_xcodebuild_auth_args() {
  xcodebuild_auth_args=()

  local key_path key_id issuer_id temp_key parsed
  key_path="$(asc_env_value \
    "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}" \
    "${APP_STORE_CONNECT_API_KEY_KEY_FILEPATH:-}" || true)"
  key_id="$(asc_env_value \
    "${APP_STORE_CONNECT_API_KEY_ID:-}" \
    "${APP_STORE_CONNECT_API_KEY_KEY_ID:-}" || true)"
  issuer_id="$(asc_env_value \
    "${APP_STORE_CONNECT_API_ISSUER_ID:-}" \
    "${APP_STORE_CONNECT_API_KEY_ISSUER_ID:-}" || true)"

  if [[ -n "$key_path" && -f "$key_path" && -n "$key_id" && -n "$issuer_id" ]]; then
    xcodebuild_auth_args=(
      -allowProvisioningUpdates
      -authenticationKeyPath "$key_path"
      -authenticationKeyID "$key_id"
      -authenticationKeyIssuerID "$issuer_id"
    )
    return 0
  fi

  if [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" ||
    ! -f "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
    return 1
  fi

  temp_key="$(mktemp "${TMPDIR:-/tmp}/hydracam-asc-key.XXXXXX.p8")"
  if ! parsed="$(
    APP_STORE_CONNECT_API_KEY_PATH="$APP_STORE_CONNECT_API_KEY_PATH" \
    ASC_AUTH_KEY_TEMP="$temp_key" \
    ruby -rjson -e '
      api_key_path = ENV.fetch("APP_STORE_CONNECT_API_KEY_PATH")
      data = JSON.parse(File.read(api_key_path))
      key_id = data["key_id"] || data["keyId"] || data["keyID"]
      issuer_id = data["issuer_id"] || data["issuerId"] || data["issuerID"]
      key = data["key"] || data["key_content"] || data["keyContent"]
      key_filepath = data["key_filepath"] || data["keyFilepath"] || data["key_file_path"]
      if key.to_s.empty? && !key_filepath.to_s.empty?
        key_path = File.expand_path(key_filepath, File.dirname(api_key_path))
        key = File.read(key_path)
      end
      abort("missing key_id, issuer_id, or key") if key_id.to_s.empty? || issuer_id.to_s.empty? || key.to_s.empty?
      File.write(ENV.fetch("ASC_AUTH_KEY_TEMP"), key)
      File.chmod(0600, ENV.fetch("ASC_AUTH_KEY_TEMP"))
      puts [ENV.fetch("ASC_AUTH_KEY_TEMP"), key_id, issuer_id].join("\t")
    '
  )"; then
    rm -f "$temp_key"
    return 1
  fi

  ASC_AUTH_TEMP_FILES+=("$temp_key")
  IFS=$'\t' read -r key_path key_id issuer_id <<< "$parsed"
  xcodebuild_auth_args=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$key_path"
    -authenticationKeyID "$key_id"
    -authenticationKeyIssuerID "$issuer_id"
  )
  return 0
}

write_ios_export_options() {
  mkdir -p "$IPA_DIR"
  cat > "$IOS_EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>generateAppStoreInformation</key>
  <false/>
  <key>manageAppVersionAndBuildNumber</key>
  <true/>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>4RRY2QT7H8</string>
  <key>testFlightInternalTestingOnly</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF
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
  if prepare_xcodebuild_auth_args; then
    rm -rf "$IOS_ARCHIVE_PATH"
    write_ios_export_options

    if [[ ${#build_flags[@]} -eq 0 ]]; then
      "$FLUTTER_BIN" build ios --release --no-codesign
    else
      "$FLUTTER_BIN" build ios --release --no-codesign "${build_flags[@]}"
    fi

    xcodebuild \
      -workspace "$ROOT_DIR/ios/Runner.xcworkspace" \
      -scheme Runner \
      -configuration Release \
      -destination "generic/platform=iOS" \
      -archivePath "$IOS_ARCHIVE_PATH" \
      "${xcodebuild_auth_args[@]}" \
      archive \
      CODE_SIGN_STYLE=Automatic \
      DEVELOPMENT_TEAM=4RRY2QT7H8 \
      CODE_SIGN_IDENTITY="Apple Distribution"

    xcodebuild \
      -exportArchive \
      -archivePath "$IOS_ARCHIVE_PATH" \
      -exportPath "$IPA_DIR" \
      -exportOptionsPlist "$IOS_EXPORT_OPTIONS_PLIST" \
      "${xcodebuild_auth_args[@]}"
  else
    if [[ ${#build_flags[@]} -eq 0 ]]; then
      "$FLUTTER_BIN" build ipa --release --export-method app-store
    else
      "$FLUTTER_BIN" build ipa --release --export-method app-store "${build_flags[@]}"
    fi
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
