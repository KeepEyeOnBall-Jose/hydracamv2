#!/usr/bin/env bash
set -euo pipefail

IOS_XCODE_DESTINATION_ID="${IOS_XCODE_DESTINATION_ID:-00008101-000A68811E43001E}"
IOS_DEVICE="${IOS_DEVICE:-AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A}"
IOS_DEVELOPMENT_TEAM="${IOS_DEVELOPMENT_TEAM:-4RRY2QT7H8}"
IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.keepeyeonball}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/ios-icon-profile}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Profile-iphoneos/Runner.app"

xcrun devicectl device info details --device "$IOS_DEVICE" --timeout 20

flutter pub get

xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Profile \
  -destination "id=$IOS_XCODE_DESTINATION_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$IOS_DEVELOPMENT_TEAM" \
  clean build

BUILT_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist")
if [[ "$BUILT_BUNDLE_ID" != "$IOS_BUNDLE_ID" ]]; then
  echo "Built app bundle ID '$BUILT_BUNDLE_ID' does not match expected '$IOS_BUNDLE_ID'." >&2
  echo "Update the Runner Profile PRODUCT_BUNDLE_IDENTIFIER or set IOS_BUNDLE_ID to the built app ID." >&2
  exit 1
fi

xcrun devicectl device install app \
  --device "$IOS_DEVICE" \
  "$APP_PATH"

echo "Installed $IOS_BUNDLE_ID from $APP_PATH"
echo "Start HydraCam from the Home Screen icon, or run:"
echo "xcrun devicectl device process launch --device '$IOS_DEVICE' --terminate-existing '$IOS_BUNDLE_ID'"
