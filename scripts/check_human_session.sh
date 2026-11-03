#!/usr/bin/env bash
# Run serial human-session validation; caller supplies remote resource limits.
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p logs/human-session
export PATH="$HOME/.local/bin:$PATH"
failed=0
run() {
  local name="$1"
  shift
  "$@" >"logs/human-session/$name.log" 2>&1
  local result=$?
  echo "$name: exit $result"
  tail -n 12 "logs/human-session/$name.log"
  if [ "$result" -ne 0 ]; then failed=1; fi
}
run format dart format --output=none --set-exit-if-changed lib/services/auth0_service.dart lib/services/user_service.dart lib/services/session_manager.dart lib/models/capture_session.dart test/services/auth0_service_test.dart test/services/auth_credential_store_test.dart test/services/user_service_test.dart test/models/capture_session_owner_test.dart test/services/session_manager_test.dart
run tests flutter test --no-pub --concurrency=1 --reporter=expanded
run analyze flutter analyze --no-pub
run bundle flutter build bundle --no-pub --target-platform=android-arm64
exit "$failed"
