#!/usr/bin/env bash
# Quality gate for the Android `court` flavor (K1 court runtime).
#
# Runs, with -PhydracamCourt=true:
#   - :app:testCourtDebugUnitTest   JVM tests (fake C1 WS server, fake C2 store)
#   - :app:ktlintCheck              Kotlin style
#   - :app:detekt                   Kotlin static analysis
#   - :app:koverVerifyCourtDebug    >= 90% line and branch coverage on court code
# The thresholds and Kover exclusions live in android/app/build.gradle.
#
# Uses $JAVA_HOME when set, else Android Studio's bundled JBR on macOS.
#
# Usage:
#   bash scripts/court_quality_gate.sh
#   bash scripts/court_quality_gate.sh --info   # extra args go to Gradle

set -uo pipefail

repo_root="$(git rev-parse --show-toplevel)"
android_dir="$repo_root/android"

if [ -z "${JAVA_HOME:-}" ]; then
  studio_jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  if [ -d "$studio_jbr" ]; then
    export JAVA_HOME="$studio_jbr"
  else
    echo "court_quality_gate: set JAVA_HOME (no Android Studio JBR found)." >&2
    exit 2
  fi
fi

echo "court_quality_gate: JAVA_HOME=$JAVA_HOME"

"$android_dir/gradlew" -p "$android_dir" \
  :app:testCourtDebugUnitTest \
  :app:ktlintCheck \
  :app:detekt \
  :app:koverVerifyCourtDebug \
  -PhydracamCourt=true \
  --console=plain \
  --continue \
  "$@"
status=$?

if [ "$status" -eq 0 ]; then
  echo "court_quality_gate: pass"
else
  echo "court_quality_gate: FAIL (exit $status)" >&2
fi
exit "$status"
