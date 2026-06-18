#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export HYDRACAM_PRIVACY_POLICY_URL="${HYDRACAM_PRIVACY_POLICY_URL:-https://store-site-ten.vercel.app/privacy.html}"
export HYDRACAM_SUPPORT_URL="${HYDRACAM_SUPPORT_URL:-https://store-site-ten.vercel.app/support.html}"
export HYDRACAM_ACCOUNT_DELETION_URL="${HYDRACAM_ACCOUNT_DELETION_URL:-https://store-site-ten.vercel.app/account-deletion.html}"

if [[ -z "${GOOGLE_PLAY_JSON_KEY:-}" || ! -f "${GOOGLE_PLAY_JSON_KEY:-}" ]]; then
  cat >&2 <<'EOF'
GOOGLE_PLAY_JSON_KEY must point to a Google Play service-account JSON file.

Create or locate the Play Console service account with upload access, then rerun:
  GOOGLE_PLAY_JSON_KEY=/path/to/play-service-account.json bash scripts/google_play_internal_release.sh
EOF
  exit 64
fi

cd "$ROOT_DIR"

bash scripts/check_store_readiness.sh upload-android
bash scripts/android_fastlane.sh internal

echo "Submitted HydraCam Android build to Google Play internal testing."
