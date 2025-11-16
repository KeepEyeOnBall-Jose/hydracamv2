#!/bin/bash
# Wrapper script to bypass sandbox issues
# This creates the .last_build_id file before Flutter tries to write it

set -e

# Get the build directory
BUILD_DIR="${TARGET_BUILD_DIR}"

# Ensure directory exists and create marker file
mkdir -p "${BUILD_DIR}"
touch "${BUILD_DIR}/.last_build_id" 2>/dev/null || true
chmod 666 "${BUILD_DIR}/.last_build_id" 2>/dev/null || true

# Call the actual Flutter build script
/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" "$@"
