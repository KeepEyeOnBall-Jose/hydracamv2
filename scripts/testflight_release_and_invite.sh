#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
HOMEBREW_RUBY_BIN="${HOMEBREW_RUBY_BIN:-/opt/homebrew/opt/ruby/bin}"
HOMEBREW_RUBY_GEMS_BIN="${HOMEBREW_RUBY_GEMS_BIN:-/opt/homebrew/lib/ruby/gems/3.4.0/bin}"

export PATH="$HOMEBREW_RUBY_BIN:$HOMEBREW_RUBY_GEMS_BIN:$PATH"

load_local_app_store_connect_env() {
  local env_file

  env_file="${HYDRACAM_ASC_ENV_FILE:-$HOME/.hydracam/secrets/app-store-connect.env}"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
  fi
}

load_local_app_store_connect_env

export HYDRACAM_PRIVACY_POLICY_URL="${HYDRACAM_PRIVACY_POLICY_URL:-https://store-site-ten.vercel.app/privacy.html}"
export HYDRACAM_SUPPORT_URL="${HYDRACAM_SUPPORT_URL:-https://store-site-ten.vercel.app/support.html}"
export HYDRACAM_ACCOUNT_DELETION_URL="${HYDRACAM_ACCOUNT_DELETION_URL:-https://store-site-ten.vercel.app/account-deletion.html}"
export TESTFLIGHT_GROUPS="${TESTFLIGHT_GROUPS:-Hydracam External Testers}"
export TESTFLIGHT_TESTERS="${TESTFLIGHT_TESTERS:-jose@keepeyeonball.com,pkosiak@gmail.com}"
export TESTFLIGHT_CHANGELOG="${TESTFLIGHT_CHANGELOG:-HydraCam 1.4.0 beta build for scaled device testing.}"
export TESTFLIGHT_DISTRIBUTE_EXTERNAL="${TESTFLIGHT_DISTRIBUTE_EXTERNAL:-true}"
ASC_AUTH_TEMP_FILES=()

cleanup_asc_auth_temp_files() {
  local temp_file

  for temp_file in "${ASC_AUTH_TEMP_FILES[@]:-}"; do
    [[ -n "$temp_file" ]] || continue
    rm -f "$temp_file"
  done
}

trap cleanup_asc_auth_temp_files EXIT

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

prepare_fastlane_api_key_json() {
  if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" &&
    -f "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
    return 0
  fi

  if ! has_direct_asc_key_triplet; then
    return 1
  fi

  local key_path key_id issuer_id temp_json
  key_path="$(asc_env_value \
    "${APP_STORE_CONNECT_API_KEY_P8_PATH:-}" \
    "${APP_STORE_CONNECT_API_KEY_KEY_FILEPATH:-}")"
  key_id="$(asc_env_value \
    "${APP_STORE_CONNECT_API_KEY_ID:-}" \
    "${APP_STORE_CONNECT_API_KEY_KEY_ID:-}")"
  issuer_id="$(asc_env_value \
    "${APP_STORE_CONNECT_API_ISSUER_ID:-}" \
    "${APP_STORE_CONNECT_API_KEY_ISSUER_ID:-}")"
  temp_json="$(mktemp "${TMPDIR:-/tmp}/hydracam-asc-key.XXXXXX.json")"

  APP_STORE_CONNECT_API_KEY_P8_PATH="$key_path" \
  APP_STORE_CONNECT_API_KEY_ID="$key_id" \
  APP_STORE_CONNECT_API_ISSUER_ID="$issuer_id" \
  ASC_AUTH_JSON_TEMP="$temp_json" \
  ruby -rjson -e '
    data = {
      key_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_ID"),
      issuer_id: ENV.fetch("APP_STORE_CONNECT_API_ISSUER_ID"),
      key: File.read(ENV.fetch("APP_STORE_CONNECT_API_KEY_P8_PATH")),
      in_house: false
    }
    File.write(ENV.fetch("ASC_AUTH_JSON_TEMP"), JSON.pretty_generate(data))
    File.chmod(0600, ENV.fetch("ASC_AUTH_JSON_TEMP"))
  '

  ASC_AUTH_TEMP_FILES+=("$temp_json")
  export APP_STORE_CONNECT_API_KEY_PATH="$temp_json"
}

if ! prepare_fastlane_api_key_json; then
  cat >&2 <<'EOF'
App Store Connect API credentials are required.

Create one in App Store Connect > Users and Access > Integrations > App Store Connect API,
then rerun this script with either:
  APP_STORE_CONNECT_API_KEY_PATH=/path/to/app-store-connect-key.json bash scripts/testflight_release_and_invite.sh

or Apple's .p8 triplet:
  APP_STORE_CONNECT_API_KEY_P8_PATH=/path/to/AuthKey_XXXXXXXXXX.p8 \
  APP_STORE_CONNECT_API_KEY_ID=XXXXXXXXXX \
  APP_STORE_CONNECT_API_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  bash scripts/testflight_release_and_invite.sh

For unattended local uploads, put those exports in:
  ~/.hydracam/secrets/app-store-connect.env
EOF
  exit 64
fi

if ! security find-identity -v -p codesigning | grep -Eq '"(Apple Distribution|iOS Distribution):' &&
  ! has_direct_asc_key_triplet &&
  [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
  cat >&2 <<'EOF'
No local "iOS Distribution" signing identity or App Store Connect signing
automation credential is available.

Open Xcode > Settings > Accounts, sign in to the Apple Developer account for
team 4RRY2QT7H8, then create/download a distribution certificate and App Store
provisioning profile for com.keepeyeonball, or configure an App Store Connect
API key before rerunning this script.
EOF
  exit 65
fi

cd "$ROOT_DIR"

bash scripts/build_store_artifacts.sh ios
bash scripts/check_store_readiness.sh upload-ios
bash scripts/ios_fastlane.sh upload_latest_beta

IFS=',' read -r -a tester_emails <<< "$TESTFLIGHT_TESTERS"
for tester_email in "${tester_emails[@]}"; do
  tester_email="$(echo "$tester_email" | xargs)"
  [[ -n "$tester_email" ]] || continue
  (
    cd "$IOS_DIR"
    bundle exec fastlane pilot add \
      --api_key_path "$APP_STORE_CONNECT_API_KEY_PATH" \
      --app_identifier com.keepeyeonball \
      --apple_id 6738280411 \
      --team_id 118432237 \
      --email "$tester_email" \
      --groups "$TESTFLIGHT_GROUPS"
  )
done

echo "Submitted HydraCam to TestFlight and added testers: $TESTFLIGHT_TESTERS"
