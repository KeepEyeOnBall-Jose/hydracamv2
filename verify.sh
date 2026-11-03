#!/bin/bash
# HydraCam Build & Test Verification Script
# Run this before deploying to ensure everything is ready.
#
# Every gated step below must exit non-zero on failure and stop the script
# (set -euo pipefail). Nothing here is allowed to reach "VERIFICATION
# COMPLETE" after a real failure, so string-matching on command output is
# not used for pass/fail decisions — only exit codes are.

set -euo pipefail

# Directories that must be `dart format --set-exit-if-changed` clean. Keep in
# sync with the set the format gate below actually checks.
readonly FORMAT_DIRS=(lib test tool integration_test)
readonly BUILD_LOG="build/verify-build.log"

fail() {
    echo "❌ $1"
    exit 1
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  HydraCam Build & Test Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Change to project directory
cd "$(dirname "$0")"
echo "📁 Project directory: $(pwd)"
echo ""

# Check Flutter installation
echo "🔍 Checking Flutter installation..."
if ! command -v flutter &> /dev/null; then
    fail "Flutter not found. Please install Flutter SDK."
fi
flutter --version | head -1
echo ""

# Run Flutter Doctor (informational only; does not gate the run)
echo "🏥 Running Flutter Doctor..."
flutter doctor --android-licenses < /dev/null || true
flutter doctor || true
echo ""

# Clean build
echo "🧹 Cleaning previous build..."
if ! flutter clean; then
    fail "flutter clean failed"
fi
echo "✅ Clean complete"
echo ""

# Get dependencies
echo "📦 Getting dependencies..."
if ! flutter pub get; then
    fail "flutter pub get failed"
fi
echo "✅ Dependencies updated"
echo ""

# Check formatting (gated on exit code; does not rewrite files)
echo "🎨 Checking dart format (${FORMAT_DIRS[*]})..."
if ! dart format --output=none --set-exit-if-changed "${FORMAT_DIRS[@]}"; then
    fail "dart format found unformatted files in: ${FORMAT_DIRS[*]} (run 'dart format ${FORMAT_DIRS[*]}' to fix)"
fi
echo "✅ Format: clean"
echo ""

# Run analyzer (gated on exit code, not "No issues found" text)
echo "🔎 Running Flutter Analyzer..."
if ! flutter analyze --no-pub; then
    fail "flutter analyze found issues"
fi
echo "✅ Analyzer: 0 issues"
echo ""

# Run full test suite (gated on exit code, not "All tests passed" text)
echo "🧪 Running Tests..."
if ! flutter test --no-pub; then
    fail "flutter test failed"
fi
echo "✅ Tests: all passed"
echo ""

# Check for connected devices (informational only; does not gate the run)
echo "📱 Checking for connected devices..."
DEVICES_OUTPUT=$(flutter devices 2>&1 || true)
DEVICE_COUNT=$(printf '%s\n' "$DEVICES_OUTPUT" | grep -c "•" || true)
if [ "$DEVICE_COUNT" -gt 0 ]; then
    echo "✅ Found $DEVICE_COUNT connected device(s)"
    printf '%s\n' "$DEVICES_OUTPUT" | grep "•" | head -3
else
    echo "⚠️  No devices connected (but can still build)"
fi
echo ""

# Build Android APK (gated on exit code; full log kept under build/, not /tmp)
echo "🔨 Building Android APK (debug)..."
mkdir -p build
if flutter build apk --debug --no-pub > "$BUILD_LOG" 2>&1; then
    echo "✅ Android APK built successfully"
    APK_PATH=$(find build/app/outputs -name "*.apk" | head -1)
    if [ -n "$APK_PATH" ]; then
        APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
        echo "   Location: $APK_PATH"
        echo "   Size: $APK_SIZE"
    fi
else
    echo "❌ Android build failed (see $BUILD_LOG for details)"
    tail -40 "$BUILD_LOG"
    fail "flutter build apk --debug failed"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ VERIFICATION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Summary:"
echo "   ✅ Flutter SDK: OK"
echo "   ✅ Format: clean"
echo "   ✅ Analyzer: 0 issues"
echo "   ✅ Tests: Passing"
echo "   ✅ Build: Success"
echo ""
echo "🚀 Ready to deploy!"
echo ""
echo "Next steps:"
echo "  • flutter run              (run on connected device)"
echo "  • flutter run -d android   (run on Android)"
echo "  • flutter run -d ios       (run on iOS)"
echo ""
echo "For release builds:"
echo "  • flutter build apk --release"
echo "  • flutter build appbundle --release"
echo ""
