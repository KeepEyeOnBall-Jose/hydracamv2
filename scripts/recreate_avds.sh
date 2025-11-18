#!/usr/bin/env bash
set -euo pipefail

# Recreate the project's AVDs on a fresh machine.
# Usage: ./scripts/recreate_avds.sh
# Requirements: Java + Android SDK command-line tools installed.
# Ensure ANDROID_SDK_ROOT is set (defaults to ~/Library/Android/sdk).

SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
CMD_SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$CMD_SDKMANAGER" ]; then
  CMD_SDKMANAGER="$SDK_ROOT/tools/bin/sdkmanager"
fi

if [ ! -x "$CMD_SDKMANAGER" ]; then
  echo "Cannot find sdkmanager. Please install Android SDK command-line tools." >&2
  exit 2
fi

echo "Using Android SDK at $SDK_ROOT"

echo "Installing platform-tools, emulator, and required system-images..."
"$CMD_SDKMANAGER" --install "platform-tools" "emulator" \
  "system-images;android-34;google_apis_playstore;arm64-v8a" \
  "system-images;android-36;google_apis_playstore;arm64-v8a" \
  --licenses

AVDMGR="$SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
if [ ! -x "$AVDMGR" ]; then
  AVDMGR="$SDK_ROOT/tools/bin/avdmanager"
fi

if [ ! -x "$AVDMGR" ]; then
  echo "Cannot find avdmanager. Please ensure Android SDK command-line tools are installed." >&2
  exit 2
fi

create_avd() {
  local name="$1" package="$2" device="$3"
  echo "Creating AVD $name (package=$package device=$device)"
  echo "no" | "$AVDMGR" create avd --force --name "$name" --package "$package" --device "$device" || true
}

echo "Creating AVDs (names match this repo):"
create_avd "Hydra_Master_API34" "system-images;android-34;google_apis_playstore;arm64-v8a" "pixel_6"
create_avd "Hydra_SlaveA_API34" "system-images;android-34;google_apis_playstore;arm64-v8a" "pixel_6"
create_avd "Hydra_SlaveB_API34" "system-images;android-34;google_apis_playstore;arm64-v8a" "pixel_6"
create_avd "Hydra_SlaveC_API34" "system-images;android-34;google_apis_playstore;arm64-v8a" "pixel_6"
create_avd "Pixel_7" "system-images;android-34;google_apis_playstore;arm64-v8a" "pixel_7"
create_avd "Medium_Phone_API_36" "system-images;android-36;google_apis_playstore;arm64-v8a" "pixel"

echo "Done. You may want to tune each AVD's config.ini (in ~/.android/avd/<name>.avd/config.ini)"
echo "If you need exact parity (snapshots, userdata images), export the AVD directory from the source machine and copy it to ~/.android/avd/ on the target machine." 
