#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-local}"

EXPECTED_IOS_BUNDLE_ID="${EXPECTED_IOS_BUNDLE_ID:-com.keepeyeonball}"
EXPECTED_ANDROID_PACKAGE="${EXPECTED_ANDROID_PACKAGE:-com.amaia23.hydracam}"
EXPECTED_DISPLAY_NAME="${EXPECTED_DISPLAY_NAME:-HydraCam}"
EXPECTED_IOS_AUTH_REDIRECT_SCHEME="${EXPECTED_IOS_AUTH_REDIRECT_SCHEME:-com.keepeyeonball}"
EXPECTED_ANDROID_AUTH_REDIRECT_SCHEME="${EXPECTED_ANDROID_AUTH_REDIRECT_SCHEME:-com.amaia23.hydracam}"
EXPECTED_VERSION="${EXPECTED_VERSION:-1.4.0+16}"
STORE_METADATA_FORMAT="HydraCamStoreArtifactMetadataV1"
EXPECTED_ANDROID_MIN_SDK="${EXPECTED_ANDROID_MIN_SDK:-24}"
EXPECTED_ANDROID_MIN_TARGET_SDK="${EXPECTED_ANDROID_MIN_TARGET_SDK:-35}"
EXPECTED_ANDROID_MIN_COMPILE_SDK="${EXPECTED_ANDROID_MIN_COMPILE_SDK:-35}"
MIN_URL_LAUNCHER_UNPIN_AGP_VERSION="${MIN_URL_LAUNCHER_UNPIN_AGP_VERSION:-8.9.1}"
EXPECTED_ANDROID_UPLOAD_CERT_SHA256="${EXPECTED_ANDROID_UPLOAD_CERT_SHA256:-51:7E:10:AD:DC:7B:EA:CA:0B:FF:90:DD:10:C8:42:95:97:BE:B3:37:F1:A4:91:81:C5:B7:46:E1:D4:7C:5B:C3}"
EXPECTED_URL_LAUNCHER_ANDROID_VERSION="${EXPECTED_URL_LAUNCHER_ANDROID_VERSION:-6.3.23}"

IOS_INFO_PLIST="$ROOT_DIR/ios/Runner/Info.plist"
IOS_PRIVACY_MANIFEST="$ROOT_DIR/ios/Runner/PrivacyInfo.xcprivacy"
IOS_PROJECT_FILE="$ROOT_DIR/ios/Runner.xcodeproj/project.pbxproj"
IOS_APP_ICON_CONTENTS="$ROOT_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
IOS_FASTLANE_APPFILE="$ROOT_DIR/ios/fastlane/Appfile"
IOS_FASTLANE_FASTFILE="$ROOT_DIR/ios/fastlane/Fastfile"
IOS_FASTLANE_README="$ROOT_DIR/ios/fastlane/README.md"
ANDROID_MANIFEST="$ROOT_DIR/android/app/src/main/AndroidManifest.xml"
ANDROID_BUILD_GRADLE="$ROOT_DIR/android/app/build.gradle"
ANDROID_SETTINGS_GRADLE="$ROOT_DIR/android/settings.gradle"
ANDROID_KEY_PROPERTIES="$ROOT_DIR/android/key.properties"
ANDROID_UPLOAD_CERT="$ROOT_DIR/android/amaia23-hydracam-upload-certificate-20260609.pem"
ANDROID_FASTLANE_APPFILE="$ROOT_DIR/android/fastlane/Appfile"
ANDROID_FASTLANE_FASTFILE="$ROOT_DIR/android/fastlane/Fastfile"
ANDROID_FASTLANE_README="$ROOT_DIR/android/fastlane/README.md"
PUBSPEC="$ROOT_DIR/pubspec.yaml"
LOGIN_SCREEN="$ROOT_DIR/lib/screens/login_screen.dart"
AUTH0_SERVICE="$ROOT_DIR/lib/services/auth0_service.dart"
STORE_PRIVACY_CHECKLIST="$ROOT_DIR/docs/control/store-privacy-and-metadata.md"
STORE_PRIVACY_DRAFT="$ROOT_DIR/docs/store/hydracam-privacy-policy.md"
STORE_SUPPORT_DRAFT="$ROOT_DIR/docs/store/hydracam-support.md"
STORE_DELETION_DRAFT="$ROOT_DIR/docs/store/hydracam-account-deletion.md"
WEB_INDEX="$ROOT_DIR/web/index.html"
WEB_MANIFEST="$ROOT_DIR/web/manifest.json"
AAB_PATH="$ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"
IPA_PATH="$ROOT_DIR/build/ios/ipa/HydraCam.ipa"
COMMON_RELEASE_INPUTS=(
  "$PUBSPEC"
  "$ROOT_DIR/pubspec.lock"
  "$ROOT_DIR/lib"
  "$ROOT_DIR/scripts/build_store_artifacts.sh"
)
ANDROID_RELEASE_INPUTS=(
  "${COMMON_RELEASE_INPUTS[@]}"
  "$ROOT_DIR/android/app/build.gradle"
  "$ROOT_DIR/android/build.gradle"
  "$ROOT_DIR/android/settings.gradle"
  "$ROOT_DIR/android/gradle.properties"
  "$ROOT_DIR/android/key.properties"
  "$ROOT_DIR/android/app/src/main/AndroidManifest.xml"
  "$ROOT_DIR/android/app/src/main/res"
  "$ROOT_DIR/android/Gemfile"
  "$ROOT_DIR/android/Gemfile.lock"
  "$ANDROID_FASTLANE_APPFILE"
  "$ANDROID_FASTLANE_FASTFILE"
  "$ROOT_DIR/scripts/android_fastlane.sh"
)
IOS_RELEASE_INPUTS=(
  "${COMMON_RELEASE_INPUTS[@]}"
  "$ROOT_DIR/ios/Runner"
  "$ROOT_DIR/ios/Runner.xcodeproj/project.pbxproj"
  "$ROOT_DIR/ios/Runner.xcworkspace/contents.xcworkspacedata"
  "$ROOT_DIR/ios/Podfile"
  "$ROOT_DIR/ios/Podfile.lock"
  "$ROOT_DIR/ios/Gemfile"
  "$ROOT_DIR/ios/Gemfile.lock"
  "$IOS_FASTLANE_APPFILE"
  "$IOS_FASTLANE_FASTFILE"
  "$ROOT_DIR/scripts/ios_fastlane.sh"
)

failures=0
warnings=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

warn() {
  printf 'WARN: %s\n' "$1"
  warnings=$((warnings + 1))
}

pass() {
  printf 'PASS: %s\n' "$1"
}

requires_ios_upload() {
  case "$MODE" in
    upload | upload-ios | ios-upload | testflight-upload)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

requires_android_upload() {
  case "$MODE" in
    upload | upload-android | android-upload | play-upload)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    pass "$label exists"
  else
    fail "$label missing at $path"
  fi
}

require_text() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if grep -Eq "$pattern" "$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

require_line() {
  local path="$1"
  local line="$2"
  local label="$3"
  if grep -Fxq "$line" "$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

key_property() {
  local path="$1"
  local key="$2"

  awk -F= -v key="$key" '$1 == key {
    sub(/^[^=]*=/, "")
    print
    exit
  }' "$path"
}

resolve_android_store_file() {
  local configured_path="$1"

  if [[ "$configured_path" = /* ]]; then
    printf '%s\n' "$configured_path"
  else
    printf '%s\n' "$ROOT_DIR/android/$configured_path"
  fi
}

gradle_int_value() {
  local path="$1"
  local key="$2"

  awk -v key="$key" '
    $0 ~ key {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+$/) {
          print $i
          exit
        }
      }
    }
  ' "$path"
}

android_gradle_plugin_version() {
  if [[ ! -f "$ANDROID_SETTINGS_GRADLE" ]]; then
    return 1
  fi
  sed -nE 's/.*id "com\.android\.application" version "([^"]+)".*/\1/p' \
    "$ANDROID_SETTINGS_GRADLE" | head -n 1
}

version_at_least() {
  local current="$1"
  local minimum="$2"
  local first second

  first="$(printf '%s\n%s\n' "$minimum" "$current" | sort -V | head -n 1)"
  second="$(printf '%s\n%s\n' "$minimum" "$current" | sort -V | tail -n 1)"
  [[ "$first" == "$minimum" && "$second" == "$current" ]]
}

is_public_https_url() {
  local url="$1"
  local host_port host

  [[ "$url" =~ ^https://[^[:space:]]+$ ]] || return 1

  host_port="${url#https://}"
  host_port="${host_port%%/*}"
  if [[ "$host_port" == \[*\] ]]; then
    host="${host_port#\[}"
    host="${host%%\]*}"
  else
    host="${host_port%%:*}"
  fi

  case "$host" in
    "" | \
    example.com | www.example.com | \
    example.org | www.example.org | \
    example.net | www.example.net | \
    localhost | 127.* | 0.0.0.0 | ::1 | \
    *.local | *.invalid | \
    your-* | your.* | changeme.*)
      return 1
      ;;
  esac

  return 0
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

has_direct_asc_key_triplet() {
  local key_path key_id issuer_id
  key_path="$(asc_env_value \
    "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}" \
    "${APP_STORE_CONNECT_API_KEY_KEY_FILEPATH:-}" || true)"
  key_id="$(asc_env_value \
    "${APP_STORE_CONNECT_API_KEY_ID:-}" \
    "${APP_STORE_CONNECT_API_KEY_KEY_ID:-}" || true)"
  issuer_id="$(asc_env_value \
    "${APP_STORE_CONNECT_API_ISSUER_ID:-}" \
    "${APP_STORE_CONNECT_API_KEY_ISSUER_ID:-}" || true)"

  [[ -n "$key_path" && -f "$key_path" && -n "$key_id" && -n "$issuer_id" ]]
}

has_app_store_connect_api_key() {
  [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" && -f "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]] ||
    has_direct_asc_key_triplet
}

find_aapt2() {
  local sdk_root candidate

  if command -v aapt2 >/dev/null 2>&1; then
    command -v aapt2
    return 0
  fi

  for sdk_root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
    [[ -n "$sdk_root" ]] || continue
    [[ -d "$sdk_root/build-tools" ]] || continue
    candidate="$(ls -1 "$sdk_root"/build-tools/*/aapt2 2>/dev/null | tail -n 1 || true)"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

newer_release_input() {
  local artifact="$1"
  shift

  local input newer
  for input in "$@"; do
    [[ -e "$input" ]] || continue
    newer="$(find "$input" -type f -newer "$artifact" -print -quit 2>/dev/null || true)"
    if [[ -n "$newer" ]]; then
      printf '%s\n' "$newer"
      return 0
    fi
  done

  return 1
}

check_store_artifact() {
  local path="$1"
  local label="$2"
  local build_hint="$3"
  local required="$4"
  shift 4

  if [[ ! -s "$path" ]]; then
    if [[ "$required" == "1" ]]; then
      fail "$label missing; run $build_hint"
    else
      warn "$label missing; run $build_hint"
    fi
    return
  fi

  local hash newer
  hash="$(shasum -a 256 "$path" | awk '{print $1}')"
  if newer="$(newer_release_input "$path" "$@")"; then
    if [[ "$required" == "1" ]]; then
      fail "$label is stale: $newer is newer than the artifact"
    else
      warn "$label may be stale: $newer is newer than the artifact"
    fi
    return
  fi

  pass "$label exists and is current: $hash"
}

metadata_value() {
  local path="$1"
  local key="$2"

  awk -F '\t' -v key="$key" '$1 == key {
    sub(/^[^\t]*\t/, "")
    print
    exit
  }' "$path"
}

metadata_issue() {
  local required="$1"
  local message="$2"

  if [[ "$required" == "1" ]]; then
    fail "$message"
  else
    warn "$message"
  fi
}

check_store_artifact_metadata() {
  local artifact_path="$1"
  local label="$2"
  local expected_platform="$3"
  local required="$4"
  local metadata_path="${artifact_path}.store-metadata.tsv"
  local actual_hash metadata_hash
  local -a mismatches=()

  if [[ ! -s "$artifact_path" ]]; then
    return 0
  fi

  if [[ ! -f "$metadata_path" ]]; then
    metadata_issue "$required" \
      "$label store metadata missing; rebuild with scripts/build_store_artifacts.sh or fastlane"
    return
  fi

  pass "$label store metadata sidecar exists"

  if [[ "$(metadata_value "$metadata_path" format)" != "$STORE_METADATA_FORMAT" ]]; then
    mismatches+=("format")
  fi
  if [[ "$(metadata_value "$metadata_path" platform)" != "$expected_platform" ]]; then
    mismatches+=("platform")
  fi

  actual_hash="$(shasum -a 256 "$artifact_path" | awk '{print $1}')"
  metadata_hash="$(metadata_value "$metadata_path" artifact_sha256)"
  if [[ "$metadata_hash" != "$actual_hash" ]]; then
    mismatches+=("artifact_sha256")
  fi

  if [[ "$(metadata_value "$metadata_path" build_name)" != "${BUILD_NAME:-}" ]]; then
    mismatches+=("build_name")
  fi
  if [[ "$(metadata_value "$metadata_path" build_number)" != "${BUILD_NUMBER:-}" ]]; then
    mismatches+=("build_number")
  fi
  if [[ "$(metadata_value "$metadata_path" hydracam_privacy_policy_url)" != "${HYDRACAM_PRIVACY_POLICY_URL:-}" ]]; then
    mismatches+=("HYDRACAM_PRIVACY_POLICY_URL")
  fi
  if [[ "$(metadata_value "$metadata_path" hydracam_support_url)" != "${HYDRACAM_SUPPORT_URL:-}" ]]; then
    mismatches+=("HYDRACAM_SUPPORT_URL")
  fi
  if [[ "$(metadata_value "$metadata_path" hydracam_account_deletion_url)" != "${HYDRACAM_ACCOUNT_DELETION_URL:-}" ]]; then
    mismatches+=("HYDRACAM_ACCOUNT_DELETION_URL")
  fi

  if [[ "${#mismatches[@]}" -gt 0 ]]; then
    metadata_issue "$required" \
      "$label store metadata mismatch: ${mismatches[*]}"
  else
    pass "$label store metadata matches the artifact and current build environment"
  fi
}

require_public_store_urls() {
  [[ -n "${HYDRACAM_PRIVACY_POLICY_URL:-}" ]] && is_public_https_url "$HYDRACAM_PRIVACY_POLICY_URL" || \
    fail "$MODE mode requires HYDRACAM_PRIVACY_POLICY_URL as a public HTTPS URL"
  [[ -n "${HYDRACAM_SUPPORT_URL:-}" ]] && is_public_https_url "$HYDRACAM_SUPPORT_URL" || \
    fail "$MODE mode requires HYDRACAM_SUPPORT_URL as a public HTTPS URL"
  [[ -n "${HYDRACAM_ACCOUNT_DELETION_URL:-}" ]] && is_public_https_url "$HYDRACAM_ACCOUNT_DELETION_URL" || \
    fail "$MODE mode requires HYDRACAM_ACCOUNT_DELETION_URL as a public HTTPS URL"
}

check_android_aab_manifest() {
  local aapt2_path tmp_dir manifest_dump first_error

  if ! aapt2_path="$(find_aapt2)"; then
    fail "Android SDK aapt2 missing; cannot inspect packaged AAB manifest"
    return
  fi

  tmp_dir="$(mktemp -d)"
  if ! unzip -p "$AAB_PATH" base/manifest/AndroidManifest.xml > "$tmp_dir/AndroidManifest.xml"; then
    rm -rf "$tmp_dir"
    fail "Android AAB does not contain base/manifest/AndroidManifest.xml"
    return
  fi

  if ! (cd "$tmp_dir" && zip -q manifest.zip AndroidManifest.xml); then
    rm -rf "$tmp_dir"
    fail "Could not prepare packaged Android manifest for inspection"
    return
  fi

  if ! manifest_dump="$(
    "$aapt2_path" dump xmltree --file AndroidManifest.xml "$tmp_dir/manifest.zip" 2>&1
  )"; then
    first_error="$(printf '%s\n' "$manifest_dump" | sed -n '1p')"
    rm -rf "$tmp_dir"
    fail "Android AAB manifest inspection failed: $first_error"
    return
  fi

  rm -rf "$tmp_dir"

  if printf '%s\n' "$manifest_dump" | grep -Fq "net.openid.appauth.RedirectUriReceiverActivity"; then
    pass "Android AAB packages the AppAuth redirect receiver"
  else
    fail "Android AAB missing AppAuth redirect receiver"
  fi

  if printf '%s\n' "$manifest_dump" | grep -Fq "Raw: \"login-callback\""; then
    pass "Android AAB packages the Auth0 redirect host"
  else
    fail "Android AAB missing Auth0 redirect host login-callback"
  fi

  if printf '%s\n' "$manifest_dump" |
    grep -Eq "android:scheme\\([^)]*\\)=\"${EXPECTED_ANDROID_AUTH_REDIRECT_SCHEME}\""; then
    pass "Android AAB packages Auth0 redirect scheme ${EXPECTED_ANDROID_AUTH_REDIRECT_SCHEME}"
  else
    fail "Android AAB missing Auth0 redirect scheme ${EXPECTED_ANDROID_AUTH_REDIRECT_SCHEME}"
  fi

  if printf '%s\n' "$manifest_dump" |
    grep -Eq 'android:scheme\([^)]*\)="com\.hydracam"'; then
    fail "Android AAB packages the generic com.hydracam redirect scheme"
  else
    pass "Android AAB omits the generic com.hydracam redirect scheme"
  fi
}

require_png_file() {
  local path="$1"
  local label="$2"

  if [[ ! -f "$path" ]]; then
    fail "$label missing at $path"
    return
  fi

  if file "$path" | grep -q "PNG image data"; then
    pass "$label is a PNG"
  else
    fail "$label must be a PNG"
  fi
}

for required_command in plutil grep shasum file keytool unzip zip; do
  if command -v "$required_command" >/dev/null 2>&1; then
    pass "command available: $required_command"
  else
    fail "command missing: $required_command"
  fi
done

if [[ "$(uname -s)" == "Darwin" ]] &&
  { [[ "$MODE" == "local" ]] || requires_ios_upload; }; then
  if command -v security >/dev/null 2>&1; then
    pass "command available: security"
    if security find-identity -v -p codesigning 2>/dev/null | \
      grep -Eq '"(Apple Distribution|iOS Distribution):'; then
      pass "iOS distribution signing identity is available"
    elif has_app_store_connect_api_key; then
      pass "App Store Connect API key is available for automatic iOS signing/provisioning"
    elif [[ "$MODE" == "local" ]] || requires_ios_upload; then
      fail "iOS distribution signing identity and App Store Connect API signing credential are unavailable"
    else
      warn "iOS distribution signing identity and App Store Connect API signing credential are unavailable"
    fi
  elif [[ "$MODE" == "local" ]] || requires_ios_upload; then
    fail "command missing: security"
  else
    warn "command missing: security"
  fi
fi

require_file "$IOS_INFO_PLIST" "iOS Info.plist"
require_file "$IOS_PRIVACY_MANIFEST" "iOS privacy manifest"
require_file "$IOS_PROJECT_FILE" "iOS Xcode project"
require_file "$IOS_APP_ICON_CONTENTS" "iOS app icon manifest"
require_file "$IOS_FASTLANE_APPFILE" "iOS fastlane Appfile"
require_file "$IOS_FASTLANE_FASTFILE" "iOS fastlane Fastfile"
require_file "$IOS_FASTLANE_README" "iOS fastlane README"
require_file "$ANDROID_MANIFEST" "Android manifest"
require_file "$ANDROID_BUILD_GRADLE" "Android app build.gradle"
require_file "$ANDROID_UPLOAD_CERT" "Android upload certificate"
require_file "$ANDROID_FASTLANE_APPFILE" "Android fastlane Appfile"
require_file "$ANDROID_FASTLANE_FASTFILE" "Android fastlane Fastfile"
require_file "$ANDROID_FASTLANE_README" "Android fastlane README"
require_file "$PUBSPEC" "pubspec.yaml"
require_file "$LOGIN_SCREEN" "Login screen"
require_file "$AUTH0_SERVICE" "Auth0 service"
require_file "$STORE_PRIVACY_CHECKLIST" "store privacy checklist"
require_file "$STORE_PRIVACY_DRAFT" "store privacy policy draft"
require_file "$STORE_SUPPORT_DRAFT" "store support page draft"
require_file "$STORE_DELETION_DRAFT" "store account deletion page draft"
require_file "$WEB_INDEX" "web index"
require_file "$WEB_MANIFEST" "web manifest"
require_file "$ROOT_DIR/scripts/build_store_artifacts.sh" "store artifact build script"
require_file "$ROOT_DIR/scripts/ios_fastlane.sh" "iOS fastlane wrapper"
require_file "$ROOT_DIR/scripts/android_fastlane.sh" "Android fastlane wrapper"

if [[ -f "$IOS_INFO_PLIST" ]]; then
  if plutil -lint "$IOS_INFO_PLIST" >/dev/null; then
    pass "iOS Info.plist is valid"
  else
    fail "iOS Info.plist is invalid"
  fi

  require_text "$IOS_INFO_PLIST" "<string>${EXPECTED_DISPLAY_NAME}</string>" \
    "iOS display name is ${EXPECTED_DISPLAY_NAME}"
  require_text "$IOS_INFO_PLIST" "<key>NSCameraUsageDescription</key>" \
    "iOS camera usage description present"
  require_text "$IOS_INFO_PLIST" "<key>NSMicrophoneUsageDescription</key>" \
    "iOS microphone usage description present"
  require_text "$IOS_INFO_PLIST" "<key>NSPhotoLibraryUsageDescription</key>" \
    "iOS photo library usage description present"
  require_text "$IOS_INFO_PLIST" "<key>NSPhotoLibraryAddUsageDescription</key>" \
    "iOS photo library add usage description present"
  require_text "$IOS_INFO_PLIST" "<key>NSLocationWhenInUseUsageDescription</key>" \
    "iOS location usage description present"
  require_text "$IOS_INFO_PLIST" "<key>NSLocalNetworkUsageDescription</key>" \
    "iOS local network usage description present"
  require_text "$IOS_INFO_PLIST" "<string>${EXPECTED_IOS_AUTH_REDIRECT_SCHEME}</string>" \
    "iOS Auth0 redirect scheme is ${EXPECTED_IOS_AUTH_REDIRECT_SCHEME}"
  if grep -Fq "<string>com.hydracam</string>" "$IOS_INFO_PLIST"; then
    fail "iOS Auth0 redirect scheme must not use generic com.hydracam"
  else
    pass "iOS Auth0 redirect scheme is not the generic com.hydracam"
  fi
  if [[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$IOS_INFO_PLIST" 2>/dev/null)" == "false" ]]; then
    pass "iOS export compliance declares no non-exempt encryption"
  else
    fail "iOS Info.plist must declare ITSAppUsesNonExemptEncryption false"
  fi
  if grep -Eq "_dartobservatory|_dartVmService" "$IOS_INFO_PLIST"; then
    fail "iOS Info.plist still declares Dart VM Bonjour services"
  else
    pass "iOS Info.plist omits Dart VM Bonjour services"
  fi
fi

if [[ -f "$IOS_PRIVACY_MANIFEST" ]]; then
  if plutil -lint "$IOS_PRIVACY_MANIFEST" >/dev/null; then
    pass "iOS privacy manifest is valid"
  else
    fail "iOS privacy manifest is invalid"
  fi

  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyAccessedAPICategoryUserDefaults" \
    "iOS privacy manifest declares UserDefaults access"
  require_text "$IOS_PRIVACY_MANIFEST" "CA92\\.1" \
    "iOS privacy manifest declares UserDefaults reason CA92.1"
  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyAccessedAPICategoryFileTimestamp" \
    "iOS privacy manifest declares file timestamp access"
  require_text "$IOS_PRIVACY_MANIFEST" "C617\\.1" \
    "iOS privacy manifest declares file timestamp reason C617.1"
  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyAccessedAPICategoryDiskSpace" \
    "iOS privacy manifest declares disk space access"
  require_text "$IOS_PRIVACY_MANIFEST" "E174\\.1" \
    "iOS privacy manifest declares low/sufficient disk-space reason E174.1"
  require_text "$IOS_PRIVACY_MANIFEST" "85F4\\.1" \
    "iOS privacy manifest declares display disk-space reason 85F4.1"
  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyCollectedDataTypePhotosorVideos" \
    "iOS privacy manifest declares photo/video collection"
  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyCollectedDataTypeAudioData" \
    "iOS privacy manifest declares audio collection"
  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyCollectedDataTypePreciseLocation" \
    "iOS privacy manifest declares precise location collection"
  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyCollectedDataTypeEmailAddress" \
    "iOS privacy manifest declares email collection"
  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyCollectedDataTypeUserID" \
    "iOS privacy manifest declares user ID collection"
  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyCollectedDataTypeDeviceID" \
    "iOS privacy manifest declares device ID collection"
  require_text "$IOS_PRIVACY_MANIFEST" "NSPrivacyCollectedDataTypePurposeAppFunctionality" \
    "iOS privacy manifest declares app functionality purpose"
  if [[ "$(plutil -extract NSPrivacyTracking raw -o - "$IOS_PRIVACY_MANIFEST" 2>/dev/null)" == "false" ]]; then
    pass "iOS privacy manifest declares no tracking"
  else
    fail "iOS privacy manifest must declare NSPrivacyTracking false"
  fi
fi

if [[ -f "$IOS_PROJECT_FILE" ]]; then
  require_text "$IOS_PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = ${EXPECTED_IOS_BUNDLE_ID};" \
    "iOS bundle identifier is ${EXPECTED_IOS_BUNDLE_ID}"
  require_text "$IOS_PROJECT_FILE" "PrivacyInfo\\.xcprivacy in Resources" \
    "iOS privacy manifest is bundled in Runner resources"
fi

if [[ -f "$IOS_FASTLANE_APPFILE" ]]; then
  require_text "$IOS_FASTLANE_APPFILE" "app_identifier\\(\"${EXPECTED_IOS_BUNDLE_ID}\"\\)" \
    "iOS fastlane Appfile targets ${EXPECTED_IOS_BUNDLE_ID}"
fi

if [[ -f "$IOS_FASTLANE_FASTFILE" ]]; then
  require_text "$IOS_FASTLANE_FASTFILE" "HYDRACAM_PRIVACY_POLICY_URL" \
    "iOS fastlane builds include the privacy policy URL when configured"
  require_text "$IOS_FASTLANE_FASTFILE" "HYDRACAM_SUPPORT_URL" \
    "iOS fastlane builds include the support URL when configured"
  require_text "$IOS_FASTLANE_FASTFILE" "HYDRACAM_ACCOUNT_DELETION_URL" \
    "iOS fastlane builds include the account deletion URL when configured"
  require_text "$IOS_FASTLANE_FASTFILE" "store-metadata\\.tsv" \
    "iOS fastlane writes store artifact metadata"
fi

if [[ -f "$IOS_FASTLANE_README" ]]; then
  require_text "$IOS_FASTLANE_README" "scripts/ios_fastlane\\.sh" \
    "iOS fastlane README points to the repo wrapper"
fi

if [[ -f "$ANDROID_MANIFEST" ]]; then
  require_text "$ANDROID_MANIFEST" "package=\"${EXPECTED_ANDROID_PACKAGE}\"" \
    "Android package is ${EXPECTED_ANDROID_PACKAGE}"
  require_text "$ANDROID_MANIFEST" "android:label=\"${EXPECTED_DISPLAY_NAME}\"" \
    "Android display name is ${EXPECTED_DISPLAY_NAME}"
  require_text "$ANDROID_MANIFEST" "android.permission.CAMERA" \
    "Android camera permission present"
  require_text "$ANDROID_MANIFEST" "android.permission.RECORD_AUDIO" \
    "Android microphone permission present"
  require_text "$ANDROID_MANIFEST" "android.permission.INTERNET" \
    "Android internet permission present"
  require_text "$ANDROID_MANIFEST" "android.permission.ACCESS_WIFI_STATE" \
    "Android Wi-Fi state permission present"
  require_text "$ANDROID_MANIFEST" "android.permission.ACCESS_FINE_LOCATION" \
    "Android fine location permission present"
  require_text "$ANDROID_MANIFEST" "android.permission.READ_MEDIA_IMAGES" \
    "Android image media permission present"
  require_text "$ANDROID_MANIFEST" "android.permission.READ_MEDIA_VIDEO" \
    "Android video media permission present"
  require_text "$ANDROID_MANIFEST" 'android:scheme="\$\{appAuthRedirectScheme\}"' \
    "Android Auth0 redirect scheme comes from the appAuthRedirectScheme placeholder"
  require_text "$ANDROID_MANIFEST" 'android:host="login-callback"' \
    "Android Auth0 redirect host is login-callback"
  if grep -Fq 'android:scheme="com.hydracam"' "$ANDROID_MANIFEST"; then
    fail "Android Auth0 redirect scheme must not use generic com.hydracam"
  else
    pass "Android Auth0 redirect scheme is not the generic com.hydracam"
  fi
fi

if [[ -f "$ANDROID_BUILD_GRADLE" ]]; then
  require_text "$ANDROID_BUILD_GRADLE" "namespace = \"${EXPECTED_ANDROID_PACKAGE}\"" \
    "Android namespace is ${EXPECTED_ANDROID_PACKAGE}"
  require_text "$ANDROID_BUILD_GRADLE" "applicationId = \"${EXPECTED_ANDROID_PACKAGE}\"" \
    "Android applicationId is ${EXPECTED_ANDROID_PACKAGE}"
  require_text "$ANDROID_BUILD_GRADLE" "appAuthRedirectScheme\"\\] = \"${EXPECTED_ANDROID_AUTH_REDIRECT_SCHEME}\"" \
    "Android AppAuth manifest placeholder is ${EXPECTED_ANDROID_AUTH_REDIRECT_SCHEME}"
  android_min_sdk="$(gradle_int_value "$ANDROID_BUILD_GRADLE" "minSdkVersion")"
  android_target_sdk="$(gradle_int_value "$ANDROID_BUILD_GRADLE" "targetSdk")"
  android_compile_sdk="$(gradle_int_value "$ANDROID_BUILD_GRADLE" "compileSdk")"
  if [[ "$android_min_sdk" == "$EXPECTED_ANDROID_MIN_SDK" ]]; then
    pass "Android minSdk is ${EXPECTED_ANDROID_MIN_SDK}"
  else
    fail "Android minSdk must be ${EXPECTED_ANDROID_MIN_SDK}; found ${android_min_sdk:-missing}"
  fi
  if [[ "$android_target_sdk" =~ ^[0-9]+$ ]] &&
    [[ "$android_target_sdk" -ge "$EXPECTED_ANDROID_MIN_TARGET_SDK" ]]; then
    pass "Android targetSdk is ${android_target_sdk} (minimum ${EXPECTED_ANDROID_MIN_TARGET_SDK})"
  else
    fail "Android targetSdk must be at least ${EXPECTED_ANDROID_MIN_TARGET_SDK}; found ${android_target_sdk:-missing}"
  fi
  if [[ "$android_compile_sdk" =~ ^[0-9]+$ ]] &&
    [[ "$android_compile_sdk" -ge "$EXPECTED_ANDROID_MIN_COMPILE_SDK" ]]; then
    pass "Android compileSdk is ${android_compile_sdk} (minimum ${EXPECTED_ANDROID_MIN_COMPILE_SDK})"
  else
    fail "Android compileSdk must be at least ${EXPECTED_ANDROID_MIN_COMPILE_SDK}; found ${android_compile_sdk:-missing}"
  fi
  require_text "$ANDROID_BUILD_GRADLE" "signingConfig = signingConfigs\\.release" \
    "Android release build uses release signing config"
  if grep -Eq "signingConfigs\\.debug|hasReleaseKeystore \\? signingConfigs\\.release" "$ANDROID_BUILD_GRADLE"; then
    fail "Android release build must not fall back to debug signing"
  else
    pass "Android release build has no debug signing fallback"
  fi
fi

if [[ -f "$ANDROID_FASTLANE_APPFILE" ]]; then
  require_text "$ANDROID_FASTLANE_APPFILE" "package_name\\(\"${EXPECTED_ANDROID_PACKAGE}\"\\)" \
    "Android fastlane Appfile targets ${EXPECTED_ANDROID_PACKAGE}"
fi

if [[ -f "$ANDROID_FASTLANE_FASTFILE" ]]; then
  require_text "$ANDROID_FASTLANE_FASTFILE" "HYDRACAM_PRIVACY_POLICY_URL" \
    "Android fastlane builds include the privacy policy URL when configured"
  require_text "$ANDROID_FASTLANE_FASTFILE" "HYDRACAM_SUPPORT_URL" \
    "Android fastlane builds include the support URL when configured"
  require_text "$ANDROID_FASTLANE_FASTFILE" "HYDRACAM_ACCOUNT_DELETION_URL" \
    "Android fastlane builds include the account deletion URL when configured"
  require_text "$ANDROID_FASTLANE_FASTFILE" "store-metadata\\.tsv" \
    "Android fastlane writes store artifact metadata"
fi

if [[ -f "$ANDROID_FASTLANE_README" ]]; then
  require_text "$ANDROID_FASTLANE_README" "scripts/android_fastlane\\.sh" \
    "Android fastlane README points to the repo wrapper"
fi

android_store_file=""
if [[ -f "$ANDROID_KEY_PROPERTIES" ]]; then
  pass "Android key.properties exists"
  android_key_alias="$(key_property "$ANDROID_KEY_PROPERTIES" "keyAlias")"
  android_store_file_config="$(key_property "$ANDROID_KEY_PROPERTIES" "storeFile")"
  android_store_password="$(key_property "$ANDROID_KEY_PROPERTIES" "storePassword")"
  android_key_password="$(key_property "$ANDROID_KEY_PROPERTIES" "keyPassword")"

  if [[ -n "$android_key_alias" ]]; then
    pass "Android key.properties has keyAlias"
  else
    fail "Android key.properties missing keyAlias"
  fi
  if [[ -n "$android_store_file_config" ]]; then
    android_store_file="$(resolve_android_store_file "$android_store_file_config")"
    if [[ -f "$android_store_file" ]]; then
      pass "Android upload keystore exists"
    else
      fail "Android upload keystore missing at configured storeFile"
    fi
  else
    fail "Android key.properties missing storeFile"
  fi
  if [[ -n "$android_store_password" ]]; then
    pass "Android key.properties has storePassword"
  else
    fail "Android key.properties missing storePassword"
  fi
  if [[ -n "$android_key_password" ]]; then
    pass "Android key.properties has keyPassword"
  else
    fail "Android key.properties missing keyPassword"
  fi
else
  fail "Android key.properties missing; release builds must use the upload key"
fi

if [[ -f "$PUBSPEC" ]]; then
  require_line "$PUBSPEC" "version: ${EXPECTED_VERSION}" \
    "pubspec version is ${EXPECTED_VERSION}"
  require_text "$PUBSPEC" "^description: Multi-device sports capture app for synchronized photo and video recording\\.$" \
    "pubspec description is release-appropriate"
  require_text "$PUBSPEC" "url_launcher:" \
    "pubspec includes url_launcher for account deletion URL handoff"
  agp_version="$(android_gradle_plugin_version || true)"
  if [[ -n "$agp_version" ]] &&
    version_at_least "$agp_version" "$MIN_URL_LAUNCHER_UNPIN_AGP_VERSION"; then
    require_text "$PUBSPEC" "url_launcher_android:" \
      "pubspec declares url_launcher_android for Android Gradle Plugin ${agp_version}"
  else
    require_line "$PUBSPEC" "  url_launcher_android: ${EXPECTED_URL_LAUNCHER_ANDROID_VERSION}" \
      "pubspec pins url_launcher_android ${EXPECTED_URL_LAUNCHER_ANDROID_VERSION} for the current Android toolchain"
  fi
fi

if [[ -f "$LOGIN_SCREEN" ]]; then
  require_text "$LOGIN_SCREEN" "Privacy Policy" \
    "Login screen exposes an in-app privacy policy path"
  require_text "$LOGIN_SCREEN" "Support" \
    "Login screen exposes an in-app support path"
  require_text "$LOGIN_SCREEN" "Request Account Deletion" \
    "Login screen exposes an account deletion request path"
  require_text "$LOGIN_SCREEN" "HYDRACAM_PRIVACY_POLICY_URL" \
    "Login screen reads the privacy policy URL Dart define"
  require_text "$LOGIN_SCREEN" "HYDRACAM_SUPPORT_URL" \
    "Login screen reads the support URL Dart define"
  require_text "$LOGIN_SCREEN" "HYDRACAM_ACCOUNT_DELETION_URL" \
    "Login screen reads the account deletion URL Dart define"
fi

if [[ -f "$AUTH0_SERVICE" ]]; then
  require_text "$AUTH0_SERVICE" "defaultValue: \"${EXPECTED_IOS_AUTH_REDIRECT_SCHEME}\"" \
    "Auth0 service defaults iOS redirect scheme to ${EXPECTED_IOS_AUTH_REDIRECT_SCHEME}"
  require_text "$AUTH0_SERVICE" "defaultValue: \"${EXPECTED_ANDROID_AUTH_REDIRECT_SCHEME}\"" \
    "Auth0 service defaults Android redirect scheme to ${EXPECTED_ANDROID_AUTH_REDIRECT_SCHEME}"
  require_text "$AUTH0_SERVICE" "authRedirectHost = \"login-callback\"" \
    "Auth0 service uses login-callback redirect host"
  if grep -Fq '"com.hydracam://login-callback"' "$AUTH0_SERVICE"; then
    fail "Auth0 service must not hard-code the generic com.hydracam redirect URI"
  else
    pass "Auth0 service omits the generic com.hydracam redirect URI"
  fi
fi

if [[ -f "$STORE_PRIVACY_CHECKLIST" ]]; then
  require_text "$STORE_PRIVACY_CHECKLIST" "Privacy Policy URL" \
    "store checklist tracks the privacy policy URL"
  require_text "$STORE_PRIVACY_CHECKLIST" "Support URL" \
    "store checklist tracks the support URL"
  require_text "$STORE_PRIVACY_CHECKLIST" "HYDRACAM_ACCOUNT_DELETION_URL" \
    "store checklist tracks the account deletion URL Dart define"
  require_text "$STORE_PRIVACY_CHECKLIST" "Photos, videos, and microphone audio" \
    "store checklist covers media and audio data"
  require_text "$STORE_PRIVACY_CHECKLIST" "Auth0 identity" \
    "store checklist covers Auth0 identity data"
  require_text "$STORE_PRIVACY_CHECKLIST" "local WebSocket" \
    "store checklist covers local-network WebSocket behavior"
fi

if [[ -f "$STORE_PRIVACY_DRAFT" ]]; then
  require_text "$STORE_PRIVACY_DRAFT" "Auth0 login identity" \
    "privacy policy draft covers Auth0 identity"
  require_text "$STORE_PRIVACY_DRAFT" "photos, videos, microphone audio" \
    "privacy policy draft covers captured media and audio"
  require_text "$STORE_PRIVACY_DRAFT" "Location and network context" \
    "privacy policy draft covers location and network context"
  require_text "$STORE_PRIVACY_DRAFT" "Diagnostics" \
    "privacy policy draft covers diagnostics"
  require_text "$STORE_PRIVACY_DRAFT" "Account And Data Deletion" \
    "privacy policy draft links account/data deletion expectations"
fi

if [[ -f "$STORE_SUPPORT_DRAFT" ]]; then
  require_text "$STORE_SUPPORT_DRAFT" "same local network or hotspot" \
    "support draft covers same-network setup"
  require_text "$STORE_SUPPORT_DRAFT" "Grant camera and microphone access" \
    "support draft covers camera and microphone permissions"
  require_text "$STORE_SUPPORT_DRAFT" "Grant local network access on iOS" \
    "support draft covers iOS local network permission"
  require_text "$STORE_SUPPORT_DRAFT" "Account And Data Deletion" \
    "support draft covers account/data deletion"
fi

if [[ -f "$STORE_DELETION_DRAFT" ]]; then
  require_text "$STORE_DELETION_DRAFT" "HYDRACAM_ACCOUNT_DELETION_URL" \
    "account deletion draft matches the release Dart define"
  require_text "$STORE_DELETION_DRAFT" "Auth0 account identity" \
    "account deletion draft covers Auth0 account data"
  require_text "$STORE_DELETION_DRAFT" "HydraCam backend user records" \
    "account deletion draft covers backend user records"
  require_text "$STORE_DELETION_DRAFT" "Uploaded session metadata" \
    "account deletion draft covers uploaded session data"
  require_text "$STORE_DELETION_DRAFT" "Verification" \
    "account deletion draft covers requester verification"
  require_text "$STORE_DELETION_DRAFT" "Retention Exceptions" \
    "account deletion draft covers retention exceptions"
fi

if [[ -f "$ROOT_DIR/scripts/build_store_artifacts.sh" ]]; then
  require_text "$ROOT_DIR/scripts/build_store_artifacts.sh" "dart-define" \
    "store build script supports Dart defines"
  require_text "$ROOT_DIR/scripts/build_store_artifacts.sh" \
    "HYDRACAM_PRIVACY_POLICY_URL=" \
    "store build script compiles the privacy policy URL when configured"
  require_text "$ROOT_DIR/scripts/build_store_artifacts.sh" \
    "HYDRACAM_SUPPORT_URL=" \
    "store build script compiles the support URL when configured"
  require_text "$ROOT_DIR/scripts/build_store_artifacts.sh" \
    "HYDRACAM_ACCOUNT_DELETION_URL=" \
    "store build script compiles the account deletion URL when configured"
  require_text "$ROOT_DIR/scripts/build_store_artifacts.sh" \
    "store-metadata\\.tsv" \
    "store build script writes store artifact metadata"
fi

if [[ -f "$WEB_MANIFEST" ]]; then
  require_text "$WEB_MANIFEST" "\"name\": \"${EXPECTED_DISPLAY_NAME}\"" \
    "web manifest name is ${EXPECTED_DISPLAY_NAME}"
  require_text "$WEB_MANIFEST" "\"short_name\": \"${EXPECTED_DISPLAY_NAME}\"" \
    "web manifest short_name is ${EXPECTED_DISPLAY_NAME}"
  require_text "$WEB_MANIFEST" "HydraCam coordinates synchronized sports photo and video capture" \
    "web manifest description is release-appropriate"
  if grep -Eq "A Flutter project|sport_cam_sync" "$WEB_MANIFEST"; then
    fail "web manifest still contains Flutter template metadata"
  else
    pass "web manifest omits Flutter template metadata"
  fi
fi

if [[ -f "$WEB_INDEX" ]]; then
  require_text "$WEB_INDEX" "<title>${EXPECTED_DISPLAY_NAME}</title>" \
    "web index title is ${EXPECTED_DISPLAY_NAME}"
  require_text "$WEB_INDEX" "apple-mobile-web-app-title\" content=\"${EXPECTED_DISPLAY_NAME}\"" \
    "web index Apple title is ${EXPECTED_DISPLAY_NAME}"
  require_text "$WEB_INDEX" "HydraCam coordinates synchronized sports photo and video capture" \
    "web index description is release-appropriate"
  if grep -Eq "A Flutter project|sport_cam_sync" "$WEB_INDEX"; then
    fail "web index still contains Flutter template metadata"
  else
    pass "web index omits Flutter template metadata"
  fi
fi

for launch_image in \
  "$ROOT_DIR/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png" \
  "$ROOT_DIR/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png" \
  "$ROOT_DIR/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png"; do
  if [[ -s "$launch_image" ]]; then
    size_bytes="$(wc -c < "$launch_image" | tr -d ' ')"
    if [[ "$size_bytes" -gt 1000 ]]; then
      pass "$(basename "$launch_image") is branded-sized (${size_bytes} bytes)"
    else
      fail "$(basename "$launch_image") still looks like a placeholder (${size_bytes} bytes)"
    fi
  else
    fail "$(basename "$launch_image") missing or empty"
  fi
done

if [[ -f "$IOS_APP_ICON_CONTENTS" ]]; then
  ios_icon_count=0
  while IFS= read -r icon_entry; do
    icon_file="${icon_entry#\"filename\":\"}"
    icon_file="${icon_file%\"}"
    ios_icon_count=$((ios_icon_count + 1))
    require_png_file \
      "$ROOT_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset/$icon_file" \
      "iOS app icon $icon_file"
  done < <(grep -o '"filename":"[^"]*"' "$IOS_APP_ICON_CONTENTS" || true)

  if [[ "$ios_icon_count" -gt 0 ]]; then
    pass "iOS app icon manifest references $ios_icon_count icon files"
  else
    fail "iOS app icon manifest references no icon files"
  fi
fi

android_icon_count=0
for launcher_icon in "$ROOT_DIR"/android/app/src/main/res/mipmap-*/ic_launcher.png; do
  [[ -e "$launcher_icon" ]] || continue
  android_icon_count=$((android_icon_count + 1))
  require_png_file "$launcher_icon" "Android launcher icon $launcher_icon"
done

if [[ "$android_icon_count" -gt 0 ]]; then
  pass "Android launcher icon set includes $android_icon_count densities"
else
  fail "Android launcher icon set is missing"
fi

check_android_artifact=0
if [[ "$MODE" == "local" ]] || requires_android_upload; then
  check_android_artifact=1
fi

check_ios_artifact=0
if [[ "$MODE" == "local" ]] || requires_ios_upload; then
  check_ios_artifact=1
fi

android_artifact_required=0
if requires_android_upload; then
  android_artifact_required=1
fi

ios_artifact_required=0
if requires_ios_upload; then
  ios_artifact_required=1
fi

if [[ "$check_android_artifact" == "1" ]]; then
  check_store_artifact "$AAB_PATH" "Android AAB" \
    "scripts/build_store_artifacts.sh android" "$android_artifact_required" \
    "${ANDROID_RELEASE_INPUTS[@]}"
  if [[ -s "$AAB_PATH" ]]; then
    check_store_artifact_metadata "$AAB_PATH" "Android AAB" \
      android "$android_artifact_required"
    check_android_aab_manifest

    if command -v keytool >/dev/null 2>&1; then
      aab_cert_sha256="$(
        keytool -printcert -jarfile "$AAB_PATH" 2>/dev/null |
          awk '/SHA256:/ {print $2; exit}'
      )"
      if [[ "$aab_cert_sha256" == "$EXPECTED_ANDROID_UPLOAD_CERT_SHA256" ]]; then
        pass "Android AAB is signed with expected upload certificate"
      else
        fail "Android AAB signing certificate does not match expected upload certificate"
      fi
    else
      fail "command missing: keytool"
    fi
  fi
fi

if [[ "$check_ios_artifact" == "1" ]]; then
  check_store_artifact "$IPA_PATH" "iOS IPA" \
    "scripts/build_store_artifacts.sh ios" "$ios_artifact_required" \
    "${IOS_RELEASE_INPUTS[@]}"
  check_store_artifact_metadata "$IPA_PATH" "iOS IPA" \
    ios "$ios_artifact_required"
fi

if [[ "$MODE" == "local" ]] || requires_ios_upload; then
  if has_app_store_connect_api_key; then
    pass "App Store Connect API key is configured"
  else
    warn "App Store Connect API key is not configured"
  fi
fi

if [[ "$MODE" == "local" ]] || requires_android_upload; then
  if [[ -n "${GOOGLE_PLAY_JSON_KEY:-}" && -f "${GOOGLE_PLAY_JSON_KEY:-}" ]]; then
    pass "GOOGLE_PLAY_JSON_KEY points to a file"
  else
    warn "GOOGLE_PLAY_JSON_KEY is not set to a readable file"
  fi
fi

if [[ -n "${HYDRACAM_PRIVACY_POLICY_URL:-}" ]] && is_public_https_url "$HYDRACAM_PRIVACY_POLICY_URL"; then
  pass "HYDRACAM_PRIVACY_POLICY_URL is set to a public HTTPS URL"
else
  warn "HYDRACAM_PRIVACY_POLICY_URL is not set to a public HTTPS URL"
fi

if [[ -n "${HYDRACAM_SUPPORT_URL:-}" ]] && is_public_https_url "$HYDRACAM_SUPPORT_URL"; then
  pass "HYDRACAM_SUPPORT_URL is set to a public HTTPS URL"
else
  warn "HYDRACAM_SUPPORT_URL is not set to a public HTTPS URL"
fi

if [[ -n "${HYDRACAM_ACCOUNT_DELETION_URL:-}" ]] && is_public_https_url "$HYDRACAM_ACCOUNT_DELETION_URL"; then
  pass "HYDRACAM_ACCOUNT_DELETION_URL is set to a public HTTPS URL"
else
  warn "HYDRACAM_ACCOUNT_DELETION_URL is not set to a public HTTPS URL"
fi

case "$MODE" in
  local)
    ;;
  upload)
    has_app_store_connect_api_key || \
      fail "upload mode requires an App Store Connect API key"
    [[ -n "${GOOGLE_PLAY_JSON_KEY:-}" && -f "${GOOGLE_PLAY_JSON_KEY:-}" ]] || \
      fail "upload mode requires GOOGLE_PLAY_JSON_KEY"
    require_public_store_urls
    ;;
  upload-ios | ios-upload | testflight-upload)
    has_app_store_connect_api_key || \
      fail "$MODE mode requires an App Store Connect API key"
    require_public_store_urls
    ;;
  upload-android | android-upload | play-upload)
    [[ -n "${GOOGLE_PLAY_JSON_KEY:-}" && -f "${GOOGLE_PLAY_JSON_KEY:-}" ]] || \
      fail "$MODE mode requires GOOGLE_PLAY_JSON_KEY"
    require_public_store_urls
    ;;
  *)
    fail "unknown mode '$MODE'; use 'local', 'upload', 'upload-ios', or 'upload-android'"
    ;;
esac

printf 'Summary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
