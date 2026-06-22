#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUESTED_LANE="${1:-${PLAY_RELEASE_LANE:-internal}}"
REQUESTED_TRACK="${2:-${PLAY_CLOSED_TRACK:-}}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/google_play_release.sh [internal|closed_beta|production_draft] [closed-track]

Environment:
  GOOGLE_PLAY_JSON_KEY              Required. Path to Play Console service-account JSON.
  HYDRACAM_PRIVACY_POLICY_URL       Optional override; defaults to current public preview URL.
  HYDRACAM_SUPPORT_URL              Optional override; defaults to current public preview URL.
  HYDRACAM_ACCOUNT_DELETION_URL     Optional override; defaults to current public preview URL.
  PLAY_CLOSED_TRACK                 Optional closed testing track name; defaults to beta.
  PLAY_RELEASE_LANE                 Optional lane when no positional lane is passed.

Examples:
  GOOGLE_PLAY_JSON_KEY=/path/play.json bash scripts/google_play_release.sh internal
  GOOGLE_PLAY_JSON_KEY=/path/play.json bash scripts/google_play_release.sh closed_beta beta
  GOOGLE_PLAY_JSON_KEY=/path/play.json bash scripts/google_play_release.sh production_draft
EOF
}

case "$REQUESTED_LANE" in
  -h | --help | help)
    usage
    exit 0
    ;;
  internal | google-play-internal | play-internal)
    FASTLANE_LANE="internal"
    READINESS_MODE="play-internal"
    RELEASE_LABEL="Google Play internal testing"
    ;;
  closed | closed_beta | beta | google-play-closed | play-closed)
    FASTLANE_LANE="closed_beta"
    READINESS_MODE="play-closed"
    export PLAY_CLOSED_TRACK="${REQUESTED_TRACK:-beta}"
    RELEASE_LABEL="Google Play closed testing track '${PLAY_CLOSED_TRACK}'"
    ;;
  production | production_draft | google-play-production | play-production)
    FASTLANE_LANE="production_draft"
    READINESS_MODE="play-production"
    RELEASE_LABEL="Google Play production draft"
    ;;
  *)
    usage >&2
    echo "Unknown Google Play release lane: $REQUESTED_LANE" >&2
    exit 64
    ;;
esac

export HYDRACAM_PRIVACY_POLICY_URL="${HYDRACAM_PRIVACY_POLICY_URL:-https://store-site-ten.vercel.app/privacy.html}"
export HYDRACAM_SUPPORT_URL="${HYDRACAM_SUPPORT_URL:-https://store-site-ten.vercel.app/support.html}"
export HYDRACAM_ACCOUNT_DELETION_URL="${HYDRACAM_ACCOUNT_DELETION_URL:-https://store-site-ten.vercel.app/account-deletion.html}"

if [[ -z "${GOOGLE_PLAY_JSON_KEY:-}" || ! -f "${GOOGLE_PLAY_JSON_KEY:-}" ]]; then
  cat >&2 <<'EOF'
GOOGLE_PLAY_JSON_KEY must point to a Google Play service-account JSON file.

Create or locate the Play Console service account with release access, then rerun:
  GOOGLE_PLAY_JSON_KEY=/path/to/play-service-account.json bash scripts/google_play_release.sh internal
EOF
  exit 64
fi

cd "$ROOT_DIR"

bash scripts/check_store_readiness.sh "$READINESS_MODE"
bash scripts/android_fastlane.sh "$FASTLANE_LANE"

echo "Submitted HydraCam Android build to ${RELEASE_LABEL}."
