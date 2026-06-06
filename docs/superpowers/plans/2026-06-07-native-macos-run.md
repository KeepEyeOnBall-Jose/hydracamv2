# Native macOS Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make HydraCam run usefully as a native macOS app on this computer, starting with a UI that reaches `runApp()` and then validating local camera, local-network, gallery, and location behavior.

**Architecture:** Keep the Flutter macOS target already present in `macos/`. Fix the current macOS startup blocker by bypassing unsupported `permission_handler` calls before `runApp()`, then add macOS privacy strings, entitlements, and a desktop camera implementation behind the existing `camera` API. Avoid broad product rewrites; this is a platform enablement slice.

**Tech Stack:** Flutter 3.44.1 / Dart 3.12.1, Xcode 26.5, CocoaPods 1.16.2, Flutter macOS target, App Sandbox entitlements, `camera`, candidate `camera_desktop`.

**Implementation outcome:** The executed scope was narrowed after planning:
HydraCam now runs natively on macOS as a controller/debug app with local camera
capture mocked. Real desktop webcam capture and any `camera_desktop` adoption
remain intentionally deferred.

---

## Current Evidence

- `flutter config --list` reports `enable-macos-desktop: true`.
- `flutter devices` sees `macOS (desktop) • macos • darwin-arm64`.
- `flutter build macos --debug` succeeds and builds `build/macos/Build/Products/Debug/HydraCam.app`.
- Launching the built binary currently hits a real startup blocker before UI:

```text
MissingPluginException(No implementation found for method requestPermissions on channel flutter.baseflow.com/permissions/methods)
#2 PermissionService.requestAllPermissions (package:hydracam/services/permission_service.dart:15:22)
#3 main.<anonymous closure> (package:hydracam/main.dart:47:9)
```

- The official `camera` package currently used by the app supports Android, iOS, and web, not macOS. `macos/Flutter/GeneratedPluginRegistrant.swift` does not register a camera plugin.
- The diagnostic build generated Flutter Swift Package Manager integration for macOS:
  - `macos/Runner.xcodeproj/project.pbxproj`
  - `macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`
  - `macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  - `macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`

## Necessary Changes

To only build a native `.app`, no code change is required; that already works.

To actually run the HydraCam UI on macOS, one code change is necessary: skip or replace `permission_handler` on macOS before `runApp()`.

To use HydraCam as a functional Mac capture/control station, additional changes are necessary: macOS Info.plist privacy strings, sandbox/network/media entitlements, a macOS camera implementation, and validation for local-network discovery and capture.

## File Structure

- Modify `lib/services/permission_service.dart`
  - Add a macOS/unsupported-desktop path so startup does not call `permission_handler` where it has no plugin implementation.
- Create `test/services/permission_service_test.dart`
  - Lock the startup behavior with a macOS target-platform test.
- Modify `macos/Runner/Info.plist`
  - Add camera, microphone, photo library, location, and local-network usage descriptions.
- Modify `macos/Runner/DebugProfile.entitlements`
  - Add debug-time network client/server, camera, audio input, location, and Photos library entitlements.
- Modify `macos/Runner/Release.entitlements`
  - Add release-time network client/server, camera, audio input, location, and Photos library entitlements.
- Modify `pubspec.yaml` and `pubspec.lock`
  - Add `camera_desktop` if the capture spike validates on this machine.
- Modify `lib/services/camera_service.dart`
  - Treat unsupported desktop flash/torch operations as nonfatal.
- Potentially modify `test/services/camera_service_failure_test.dart`
  - Cover unsupported flash/torch behavior if that file remains part of the active branch.
- Keep or intentionally revert the generated macOS SPM files listed in Current Evidence after deciding whether this branch owns the Flutter 3.44 migration artifact.

## Task 1: Preserve Worktree Boundaries

**Files:**
- Inspect only: repository root

- [ ] **Step 1: Record current dirty state**

Run:

```bash
git status -sb
```

Expected: Existing user-owned changes remain visible. Do not stage unrelated files.

- [ ] **Step 2: Separate generated macOS SPM changes**

Run:

```bash
git diff --stat -- macos/Runner.xcodeproj/project.pbxproj macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
find macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm macos/Runner.xcworkspace/xcshareddata/swiftpm -maxdepth 4 -type f -print
```

Expected: Only the Flutter SPM package reference, Xcode scheme prepare action, and two `Package.resolved` files are shown for the macOS generated change.

## Task 2: Fix macOS Startup Before `runApp()`

**Files:**
- Modify: `lib/services/permission_service.dart`
- Create: `test/services/permission_service_test.dart`

- [ ] **Step 1: Add the failing startup test**

Create `test/services/permission_service_test.dart`:

```dart
import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/permission_service.dart";

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test("requestAllPermissions skips unsupported macOS permission handler", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final bool granted = await PermissionService.requestAllPermissions();

    expect(granted, isTrue);
  });
}
```

- [ ] **Step 2: Run the new test and verify it fails**

Run:

```bash
flutter test test/services/permission_service_test.dart
```

Expected before implementation: failure from `MissingPluginException` or another method-channel error caused by `permission_handler`.

- [ ] **Step 3: Implement the macOS bypass**

Update `lib/services/permission_service.dart`:

```dart
import "package:flutter/foundation.dart";
import "package:permission_handler/permission_handler.dart";
import "package:permission_handler/permission_handler.dart"
    as permission_handler;
import "log_service.dart";

// ignore: avoid_classes_with_only_static_members
class PermissionService {
  /// Requests the permissions required for initial app use.
  static Future<bool> requestAllPermissions() async {
    if (_shouldUseNativeResourcePrompts) {
      LogService.instance.registerLog(
        "Skipping permission_handler startup request on ${defaultTargetPlatform.name}; "
        "native platform APIs will request resource access on demand.",
        function: "requestAllPermissions",
        file: "PermissionService",
      );
      return true;
    }

    final permissions = <Permission>[
      Permission.camera,
      Permission.microphone,
    ];

    final statuses = await permissions.request();
    final grantedPermissions = statuses.entries
        .where((entry) => entry.value.isGranted)
        .map((entry) => entry.key.toString())
        .toList();

    final deniedPermissions = statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key.toString())
        .toList();

    final logMessage = "Permission request completed.\n"
        "Granted: $grantedPermissions\n"
        "Denied: $deniedPermissions";

    LogService.instance.registerLog(
      logMessage,
      function: "requestAllPermissions",
      file: "PermissionService",
    );

    return statuses.values.every((status) => status.isGranted);
  }

  static bool get _shouldUseNativeResourcePrompts {
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Opens the app settings page.
  static Future<void> openAppSettings() async {
    if (_shouldUseNativeResourcePrompts) {
      LogService.instance.registerLog(
        "Skipping permission_handler openAppSettings on ${defaultTargetPlatform.name}.",
        function: "openAppSettings",
        file: "PermissionService",
      );
      return;
    }

    await permission_handler.openAppSettings();
  }
}
```

- [ ] **Step 4: Verify startup test passes**

Run:

```bash
flutter test test/services/permission_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Verify native UI reaches `runApp()`**

Run:

```bash
flutter build macos --debug
ruby -rtimeout -e 'timeout = Integer(ARGV.shift); Timeout.timeout(timeout) { system(*ARGV); exit($?.exitstatus || 0) } rescue Timeout::Error; warn "TIMEOUT after #{timeout}s: #{ARGV.join(" ")}"; exit 124' 20 build/macos/Build/Products/Debug/HydraCam.app/Contents/MacOS/HydraCam
```

Expected: No `MissingPluginException` from `permission_handler`. The timeout is acceptable because the GUI process stays open.

## Task 3: Add macOS Privacy Strings

**Files:**
- Modify: `macos/Runner/Info.plist`

- [ ] **Step 1: Add Info.plist keys**

Add these entries before `</dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>HydraCam uses the camera to capture synchronized sports photos and videos.</string>
<key>NSMicrophoneUsageDescription</key>
<string>HydraCam uses the microphone when recording videos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>HydraCam reads the photo library when you choose existing media.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>HydraCam saves captured media to your photo library.</string>
<key>NSLocationUsageDescription</key>
<string>HydraCam can attach location context to capture sessions when requested.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>HydraCam uses the local network to discover and synchronize nearby camera devices.</string>
```

- [ ] **Step 2: Validate plist syntax**

Run:

```bash
plutil -lint macos/Runner/Info.plist
plutil -p macos/Runner/Info.plist
```

Expected: `OK` from lint, and the added keys visible in `plutil -p`.

## Task 4: Add macOS Sandbox Entitlements

**Files:**
- Modify: `macos/Runner/DebugProfile.entitlements`
- Modify: `macos/Runner/Release.entitlements`

- [ ] **Step 1: Update debug entitlements**

`macos/Runner/DebugProfile.entitlements` should include:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.cs.allow-jit</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.personal-information.location</key>
<true/>
<key>com.apple.security.personal-information.photos-library</key>
<true/>
```

- [ ] **Step 2: Update release entitlements**

`macos/Runner/Release.entitlements` should include:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.personal-information.location</key>
<true/>
<key>com.apple.security.personal-information.photos-library</key>
<true/>
```

- [ ] **Step 3: Validate entitlement syntax**

Run:

```bash
plutil -lint macos/Runner/DebugProfile.entitlements
plutil -lint macos/Runner/Release.entitlements
```

Expected: both files report `OK`.

## Task 5: Add a macOS Camera Implementation

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `lib/services/camera_service.dart`
- Test: `test/services/camera_service_failure_test.dart`

- [ ] **Step 1: Add desktop camera dependency**

Run:

```bash
flutter pub add camera_desktop:^1.1.7
```

Expected: `pubspec.yaml` contains `camera_desktop: ^1.1.7`, and `pubspec.lock` resolves the package.

- [ ] **Step 2: Regenerate macOS plugins**

Run:

```bash
flutter build macos --debug
```

Expected: build succeeds and `macos/Flutter/GeneratedPluginRegistrant.swift` registers the desktop camera plugin or its native package integration.

- [ ] **Step 3: Harden unsupported flash/torch handling**

Update `_setFlashModeIfSupported` in `lib/services/camera_service.dart`:

```dart
  Future<bool> _setFlashModeIfSupported(
      FlashMode mode, String operation) async {
    final controller = _controller;
    if (controller == null || _flashAvailable == false) {
      return false;
    }

    try {
      await controller.setFlashMode(mode);
      _flashAvailable = true;
      return true;
    } on UnimplementedError catch (error) {
      _flashAvailable = false;
      LogService.instance.registerLog(
          "Flash is unavailable for $operation on this platform; continuing without flash: $error");
      return false;
    } on CameraException catch (error) {
      if (_isMissingFlashCapability(error)) {
        _flashAvailable = false;
        LogService.instance.registerLog(
            "Flash is unavailable for $operation; continuing without flash: $error");
        return false;
      }
      rethrow;
    }
  }

  bool _isMissingFlashCapability(CameraException error) {
    final description = error.description?.toLowerCase() ?? "";
    final code = error.code.toLowerCase();
    return code.contains("unimplemented") ||
        code.contains("unsupported") ||
        description.contains("not supported") ||
        description.contains("unsupported") ||
        (code == "setflashmodefailed" &&
            description.contains("flash") &&
            description.contains("capabilities"));
  }
```

- [ ] **Step 4: Add or extend camera-service test**

Add a fake camera-platform assertion to `test/services/camera_service_failure_test.dart` that initializes a fake camera and throws a `CameraException("unsupported", "Flash mode is not supported")` from `setFlashMode`; then call `startRecordingVideo(enableFlash: true)` or the narrowest existing helper that reaches `_setFlashModeIfSupported`.

Expected: unsupported flash does not fail the capture operation.

## Task 6: Validate Native Mac Runtime Features

**Files:**
- Create: `logs/verification-runs/<timestamp>-native-macos-run/README.md`

- [ ] **Step 1: Run analyzer and targeted tests**

Run:

```bash
flutter analyze
flutter test test/services/permission_service_test.dart
flutter test test/services/camera_service_failure_test.dart
```

Expected: all pass. If unrelated dirty-checkout changes fail analyzer or tests, record the exact failing file and error in the verification run.

- [ ] **Step 2: Build and launch macOS app**

Run:

```bash
flutter build macos --debug
/usr/bin/open -n build/macos/Build/Products/Debug/HydraCam.app
pgrep -fl HydraCam
```

Expected: `HydraCam.app` launches and `pgrep` shows a native process.

- [ ] **Step 3: Verify camera enumeration and capture on this Mac**

Manual check:

1. Open the camera screen in the native macOS app.
2. Grant camera and microphone prompts when macOS asks.
3. Confirm at least one camera appears.
4. Capture one photo.
5. Record a 3-5 second video.
6. Confirm files appear under the app documents `session_<guid>` folder.

Record screenshots and terminal evidence under:

```text
logs/verification-runs/<timestamp>-native-macos-run/
```

- [ ] **Step 4: Verify local-network mode**

Manual check:

1. Start master mode on the Mac.
2. Allow local-network access if macOS prompts.
3. Confirm port `4040` listens and UDP discovery on `4041` does not error.
4. Connect one mobile slave on the same network.
5. Trigger a photo command.

Useful commands:

```bash
lsof -nP -iTCP:4040 -sTCP:LISTEN
log stream --style compact --predicate 'process == "HydraCam"' --info
```

Expected: the Mac can act as master and a mobile slave can connect.

- [ ] **Step 5: Verify signed entitlements on built app**

Run:

```bash
codesign -d --entitlements :- build/macos/Build/Products/Debug/HydraCam.app
```

Expected: the signed app includes the debug entitlements from Task 4.

## Task 7: Document the Native Mac Status

**Files:**
- Modify: `docs/control/status-and-roadmap.md`

- [ ] **Step 1: Update platform status**

Add a short macOS status entry:

```markdown
- macOS native desktop: Debug build launches on this Mac. Startup is unblocked by skipping unsupported `permission_handler` macOS requests. Capture/local-network status is tracked by `logs/verification-runs/<timestamp>-native-macos-run/`.
```

- [ ] **Step 2: Validate docs-only formatting**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

## Final Validation Gate

Run:

```bash
git status -sb
flutter analyze
flutter test test/services/permission_service_test.dart
flutter test test/services/camera_service_failure_test.dart
flutter build macos --debug
git diff --check
```

Expected:

- Native macOS build succeeds.
- App launch no longer logs `MissingPluginException` for `permission_handler`.
- Camera and local-network checks have a run-specific evidence pack if those features are claimed as working.
- Generated macOS SPM files are either intentionally included in the branch or intentionally reverted before staging.
