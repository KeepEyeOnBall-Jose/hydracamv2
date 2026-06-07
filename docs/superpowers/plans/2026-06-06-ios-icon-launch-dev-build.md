# iOS Icon Launch Dev Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let HydraCam start from the iOS Home Screen icon on a physical iPhone by installing an icon-launchable Profile/Release-style development build, while keeping Debug launches scoped to Flutter tooling or Xcode.

**Architecture:** Do not try to make an iOS Flutter Debug build behave like a standalone app. Flutter Debug uses a JIT/debug engine path and can show the "debug mode only from Flutter tooling or Xcode" failure when launched directly from SpringBoard. Keep Debug for `flutter run`, and add a repeatable Profile-mode physical-device install path for icon launches. Align the iOS host with the current Flutter 3.44 template so scene lifecycle startup is not another variable.

**Tech Stack:** Flutter 3.44.1 stable, Dart 3.12.1, Xcode 26.5, iOS Profile/Release AOT builds, `xcodebuild`, `xcrun devicectl`, existing HydraCam evidence packs.

---

## Current Evidence

- Local tooling on 2026-06-06: Flutter `3.44.1`, Xcode `26.5`.
- Paired physical device: Jose/Jose Ramon iPhone, UDID `00008101-000A68811E43001E`, CoreDevice ID `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`, iPhone 12 Pro, iOS 26.4.2.
- Existing run evidence: `logs/verification-runs/2026-06-06-iphone-personal-team-debug/run-summary.md` proves `flutter run --debug` can launch, request permissions, enter master fallback, capture media, and upload successfully.
- Existing limitation: that evidence used Debug through Flutter tooling. It does not prove a Home Screen icon launch.
- Superseding status as of 2026-06-07: the broad physical-iOS white-screen
  blocker has newer iPhone/iPad working evidence. Treat future iOS work as
  release/profile launch, signing, local-network, capture, and two-device smoke
  validation unless a fresh white-screen failure is reproduced with logs.
- Existing dirty native changes already include Flutter 3.44 Swift Package/implicit-engine migration pieces in `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`, `ios/Runner/AppDelegate.swift`, and `ios/Runner/Info.plist`.
- Fresh Flutter 3.44.1 template comparison shows the scene manifest should point to `$(PRODUCT_MODULE_NAME).SceneDelegate` and a `SceneDelegate` class must exist. The current repo has the manifest but no `SceneDelegate` class, and currently points at `FlutterSceneDelegate` directly.

## File Structure

- Modify: `ios/Runner/AppDelegate.swift`
  - Keep the Flutter 3.44 `FlutterImplicitEngineDelegate` AppDelegate pattern.
  - Add the missing `SceneDelegate` class in the same Swift file to avoid touching the Xcode project file just to add a one-line Swift source file.
- Modify: `ios/Runner/Info.plist`
  - Change `UISceneDelegateClassName` from `FlutterSceneDelegate` to `$(PRODUCT_MODULE_NAME).SceneDelegate`.
  - Keep existing HydraCam permission strings and URL scheme entries.
- Review and likely keep: `ios/Runner.xcodeproj/project.pbxproj`
  - Keep Flutter 3.44 Swift Package references if they continue to match a fresh template.
  - Keep iOS deployment target `13.0`.
  - Do not rely on Debug bundle ID changes for icon launch.
- Add or track if the SPM migration is kept:
  - `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  - `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Create: `scripts/ios_icon_launch_dev.sh`
  - Build and install a Profile configuration app on the selected iPhone.
  - Default to the personal development team and dev bundle ID used in the successful debug run, but allow environment overrides.
  - Use separate IDs for `xcodebuild` and `devicectl`: the iPhone hardware UDID for Xcode destinations, and the CoreDevice ID for devicectl.
- Modify: `DISTRIBUTION_RUNBOOK.md`
  - Document the rule: Debug is tooling-only; icon testing uses Profile or Release.
  - Add exact commands for the new script and evidence capture.
- Modify: `ios/fastlane/Fastfile`
  - Replace or supplement the current Debug-oriented `device` lane with an icon-launchable Profile lane.
- Modify: `lib/services/log_service.dart`
  - Emit non-release logs through `dart:developer.log` so Profile icon launches can leave startup breadcrumbs in device console output.
  - Keep existing in-memory log list and Debug console output.
- Create: `test/services/log_service_test.dart`
  - Cover log retention and clearing. This does not prove OS log output, but prevents regressions in the service while changing it.
- Modify: `docs/control/status-and-roadmap.md`
  - Replace the broad "iOS physical-device white screen" status with the narrower result after verification: Debug works only through tooling; Profile icon-launch status passed/failed/blocked with evidence path.

## Task 1: Baseline and Protect the Current Debug Evidence

**Files:**
- Read: `logs/verification-runs/2026-06-06-iphone-personal-team-debug/run-summary.md`
- Read: `docs/control/evidence-first-loop.md`
- Create: `logs/verification-runs/<timestamp>-ios-icon-profile-launch/`

- [ ] **Step 1: Capture current worktree state**

Run:

```bash
git status -sb
```

Expected: existing user-owned dirty files are visible before new edits:

```text
 M ios/Runner.xcodeproj/project.pbxproj
 M ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
 M ios/Runner/AppDelegate.swift
 M ios/Runner/Info.plist
?? ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/
?? ios/Runner.xcworkspace/xcshareddata/swiftpm/
?? logs/verification-runs/2026-06-06-iphone-personal-team-debug/
```

- [ ] **Step 2: Start a real-hardware evidence pack**

Run:

```bash
python3 scripts/evidence_pack.py start \
  --item "Verify iOS icon-launchable Profile build" \
  --slug ios-icon-profile-launch \
  --source "docs/control/status-and-roadmap.md#release-blockers" \
  --tier A \
  --acceptance "Debug launch remains available through flutter run or Xcode only" \
  --acceptance "Profile build installs on the physical iPhone" \
  --acceptance "App starts from the Home Screen icon or devicectl launch without Flutter tooling" \
  --acceptance "HydraCam reaches the first functional app screen, not the Flutter debug tooling message" \
  --acceptance "Startup evidence includes device model, OS, launch video or screenshots, and device or app logs"
```

Expected: command prints the new run directory path, for example:

```text
logs/verification-runs/20260606-2300-ios-icon-profile-launch
```

Save that path as `RUN_DIR` for later steps:

```bash
export RUN_DIR=logs/verification-runs/20260606-2300-ios-icon-profile-launch
```

- [ ] **Step 3: Record the iPhone under test**

Run:

```bash
python3 scripts/evidence_pack.py add-device "$RUN_DIR" \
  --name "Jose/Jose Ramon iPhone" \
  --kind "iOS physical device" \
  --identifier "00008101-000A68811E43001E" \
  --role "single app icon-launch device" \
  --os "iOS 26.4.2" \
  --note "CoreDevice ID AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A"
```

Expected: command prints the same `RUN_DIR`.

- [ ] **Step 4: Copy the previous Debug-only evidence summary into the new evidence notes**

Append this text to `$RUN_DIR/summary.md`:

```markdown

## Baseline Debug Evidence

- Existing run: `logs/verification-runs/2026-06-06-iphone-personal-team-debug/run-summary.md`.
- Result: `flutter run -d 00008101-000A68811E43001E --debug --no-pub -t lib/main.dart` launched and attached to the Dart VM Service.
- Functional proof from that run: permissions granted, `SlaveScreen(isAutoMode=true)` loaded, master fallback started WebSocket port 4040, session ID 466/GUID f60e4a7a-ec8e-4897-8943-43dc0325e2d6 created, photo captured/saved/uploaded, video recording started.
- Limitation: this was not a Home Screen icon launch and should not be used as proof that Debug builds can start standalone.
```

Expected: the new evidence pack now distinguishes Debug-through-tooling from icon-launch proof.

- [ ] **Step 5: Commit only if creating the evidence pack is part of the implementation branch**

Run:

```bash
git status -sb
```

Expected: the new evidence pack appears as untracked or modified. Do not commit it yet if the branch policy is to commit implementation and evidence together at the end.

## Task 2: Align iOS Scene Startup With Flutter 3.44

**Files:**
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `ios/Runner/Info.plist`
- Review: `ios/Runner.xcodeproj/project.pbxproj`
- Review: `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`

- [ ] **Step 1: Update AppDelegate to define the scene delegate class**

Replace `ios/Runner/AppDelegate.swift` with:

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

class SceneDelegate: FlutterSceneDelegate {
}
```

Expected: this keeps the current Flutter 3.44 AppDelegate pattern and provides a module-scoped `SceneDelegate` without adding another Swift file to the Xcode project.

- [ ] **Step 2: Point the scene manifest at the module-scoped SceneDelegate**

In `ios/Runner/Info.plist`, change only this value:

```xml
<key>UISceneDelegateClassName</key>
<string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
```

Expected: all existing HydraCam keys stay intact, including camera, microphone, photo library, location, URL scheme, launch storyboard, and status bar keys.

- [ ] **Step 3: Verify the Swift Package migration files are intentionally tracked**

Run:

```bash
git status -sb
git diff -- ios/Runner.xcodeproj/project.pbxproj ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme ios/Runner/AppDelegate.swift ios/Runner/Info.plist
```

Expected:
- AppDelegate has only the scene delegate addition on top of the Flutter 3.44 implicit-engine pattern.
- Info.plist uses `$(PRODUCT_MODULE_NAME).SceneDelegate`.
- Project and scheme Swift Package changes are either retained because they match Flutter 3.44 output, or explicitly deferred if execution shows they are not needed.

- [ ] **Step 4: Run static checks for native-host edits**

Run:

```bash
python3 scripts/evidence_pack.py run "$RUN_DIR" -- git diff --check -- \
  ios/Runner/AppDelegate.swift \
  ios/Runner/Info.plist \
  ios/Runner.xcodeproj/project.pbxproj \
  ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
```

Expected: exit code `0`.

- [ ] **Step 5: Commit the native launch-host correction**

Run:

```bash
git add \
  ios/Runner/AppDelegate.swift \
  ios/Runner/Info.plist \
  ios/Runner.xcodeproj/project.pbxproj \
  ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme \
  ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
  ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "fix: align iOS scene launch host with Flutter template"
```

Expected: commit includes only iOS native host/template alignment. If unrelated user edits are still mixed into any file, use partial staging instead of the broad `git add`.

## Task 3: Add an Icon-Launchable Profile Install Script

**Files:**
- Create: `scripts/ios_icon_launch_dev.sh`
- Modify: `DISTRIBUTION_RUNBOOK.md`

- [ ] **Step 1: Create the script**

Create `scripts/ios_icon_launch_dev.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

IOS_XCODE_DESTINATION_ID="${IOS_XCODE_DESTINATION_ID:-00008101-000A68811E43001E}"
IOS_DEVICE="${IOS_DEVICE:-AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A}"
IOS_DEVELOPMENT_TEAM="${IOS_DEVELOPMENT_TEAM:-8T78Y2X37H}"
IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.vectorblanco.hydracam.dev}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/ios-icon-profile}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Profile-iphoneos/Runner.app"

if ! xcrun devicectl device info details --device "$IOS_DEVICE" --timeout 20 >/dev/null; then
  echo "iOS device '$IOS_DEVICE' was not found by devicectl." >&2
  echo "Set IOS_DEVICE to the CoreDevice ID, hardware UDID, device name, or DNS name shown by: xcrun devicectl list devices" >&2
  exit 1
fi

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
  PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_ID" \
  clean build

xcrun devicectl device install app \
  --device "$IOS_DEVICE" \
  "$APP_PATH"

echo "Installed $IOS_BUNDLE_ID from $APP_PATH"
echo "Start HydraCam from the Home Screen icon, or run:"
echo "xcrun devicectl device process launch --device '$IOS_DEVICE' --terminate-existing '$IOS_BUNDLE_ID'"
```

Expected: the script builds `Profile`, not `Debug`.

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x scripts/ios_icon_launch_dev.sh
```

Expected: `ls -l scripts/ios_icon_launch_dev.sh` shows executable bits.

- [ ] **Step 3: Shell-check the script syntax**

Run:

```bash
python3 scripts/evidence_pack.py run "$RUN_DIR" -- bash -n scripts/ios_icon_launch_dev.sh
```

Expected: exit code `0`.

- [ ] **Step 4: Document Debug versus icon launch**

Add this section to `DISTRIBUTION_RUNBOOK.md` under `## Release Gates` or near the iOS setup section:

```markdown
## Physical iPhone Development Launch Modes

Debug builds are for Flutter tooling or Xcode only. If a Debug build is started
directly from the Home Screen icon, iOS/Flutter can show a message that the
debug FlutterEngine cannot be created without Flutter tooling or Xcode. Treat
that as expected Debug-mode behavior, not as an app-runtime smoke pass.

For Home Screen icon testing before TestFlight, install a Profile build:

```bash
IOS_XCODE_DESTINATION_ID=00008101-000A68811E43001E \
IOS_DEVICE=AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A \
IOS_DEVELOPMENT_TEAM=8T78Y2X37H \
IOS_BUNDLE_ID=com.vectorblanco.hydracam.dev \
scripts/ios_icon_launch_dev.sh
```

After install, start HydraCam by tapping the iOS icon. For repeatable command
evidence without attaching Flutter tooling:

```bash
xcrun devicectl device process launch \
  --device AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A \
  --terminate-existing \
  com.vectorblanco.hydracam.dev
```

Use `flutter run -d <ios-udid> --debug` only when hot reload, Dart VM Service,
or Flutter debugger attachment is required.
```

Expected: the runbook no longer implies the existing Debug `device` lane is an icon-launch path.

- [ ] **Step 5: Commit the script and runbook**

Run:

```bash
git add scripts/ios_icon_launch_dev.sh DISTRIBUTION_RUNBOOK.md
git commit -m "chore: add iOS profile icon launch workflow"
```

Expected: commit contains only the new script and docs.

## Task 4: Update Fastlane to Stop Treating Debug as the Physical Icon Build

**Files:**
- Modify: `ios/fastlane/Fastfile`

- [ ] **Step 1: Replace the current Debug device lane with Profile semantics**

In `ios/fastlane/Fastfile`, replace the current `device` lane body:

```ruby
  desc "Build for physical device"
  lane :device do
    build_app(
      workspace: "Runner.xcworkspace",
      scheme: "Runner",
      configuration: "Debug",
      sdk: "iphoneos",
      destination: "generic/platform=iOS",
      skip_codesigning: true,
      skip_package_ipa: true
    )
  end
```

with:

```ruby
  desc "Build an icon-launchable Profile app for physical iPhone development"
  lane :device do
    build_app(
      workspace: "Runner.xcworkspace",
      scheme: "Runner",
      configuration: "Profile",
      sdk: "iphoneos",
      destination: "generic/platform=iOS",
      export_method: "development",
      skip_package_ipa: true
    )
  end
```

Expected: `fastlane ios device` no longer produces a Debug build that is expected to launch from the icon.

- [ ] **Step 2: Validate Ruby syntax**

Run:

```bash
python3 scripts/evidence_pack.py run "$RUN_DIR" -- ruby -c ios/fastlane/Fastfile
```

Expected: output contains:

```text
Syntax OK
```

- [ ] **Step 3: Commit the lane correction**

Run:

```bash
git add ios/fastlane/Fastfile
git commit -m "chore: make iOS device lane profile-based"
```

Expected: commit includes only `ios/fastlane/Fastfile`.

## Task 5: Make Profile Startup Logs Visible Without Flutter Tooling

**Files:**
- Modify: `lib/services/log_service.dart`
- Create: `test/services/log_service_test.dart`

- [ ] **Step 1: Update LogService to log in non-release builds**

Replace `lib/services/log_service.dart` with:

```dart
import "dart:collection";
import "dart:developer" as developer;

import "package:flutter/foundation.dart";

/// A singleton service to manage application logs.
class LogService {
  static final LogService _instance = LogService._internal();
  final List<Map<String, dynamic>> _logs = [];

  LogService._internal();

  /// Provides the single instance of the log service.
  static LogService get instance => _instance;

  /// Registers a log entry.
  ///
  /// [message]: The log message.
  /// [timestamp]: Timestamp of the log, defaults to the current time.
  /// [function]: The optional function name that generated the log.
  /// [file]: The optional file name that generated the log.
  void registerLog(
    String message, {
    DateTime? timestamp,
    String? function,
    String? file,
  }) {
    final entryTimestamp = timestamp ?? DateTime.now();
    final logEntry = {
      "message": message,
      "timestamp": entryTimestamp,
      "function": function,
      "file": file,
    };
    _logs.add(logEntry);

    if (!kReleaseMode) {
      developer.log(
        message,
        name: file ?? "HydraCam",
        time: entryTimestamp,
      );
    }

    if (kDebugMode) {
      debugPrint("Log registered: $logEntry");
    }
  }

  /// Retrieves all logs in a read-only format.
  UnmodifiableListView<Map<String, dynamic>> get logs =>
      UnmodifiableListView(_logs);

  /// Clears all logs.
  void clearLogs() {
    _logs.clear();
  }
}
```

Expected: Debug still prints to Flutter tooling, Profile emits developer logs, Release avoids verbose runtime logging.

- [ ] **Step 2: Add a focused LogService test**

Create `test/services/log_service_test.dart`:

```dart
import "package:flutter_test/flutter_test.dart";
import "package:hydracamv2/services/log_service.dart";

void main() {
  setUp(() {
    LogService.instance.clearLogs();
  });

  test("registerLog stores message, timestamp, function, and file", () {
    final timestamp = DateTime(2026, 6, 6, 21, 30);

    LogService.instance.registerLog(
      "Profile startup marker",
      timestamp: timestamp,
      function: "main",
      file: "main.dart",
    );

    expect(LogService.instance.logs, hasLength(1));
    expect(LogService.instance.logs.single["message"], "Profile startup marker");
    expect(LogService.instance.logs.single["timestamp"], timestamp);
    expect(LogService.instance.logs.single["function"], "main");
    expect(LogService.instance.logs.single["file"], "main.dart");
  });

  test("clearLogs removes stored entries", () {
    LogService.instance.registerLog("temporary entry");

    LogService.instance.clearLogs();

    expect(LogService.instance.logs, isEmpty);
  });
}
```

Expected: the test exercises existing behavior while allowing the implementation to change console output.

- [ ] **Step 3: Run focused Dart validation**

Run:

```bash
python3 scripts/evidence_pack.py run "$RUN_DIR" -- flutter analyze --no-pub
python3 scripts/evidence_pack.py run "$RUN_DIR" -- flutter test --no-pub test/services/log_service_test.dart test/platform_setup_test.dart
```

Expected: analyzer passes and both focused tests pass.

- [ ] **Step 4: Commit logging support**

Run:

```bash
git add lib/services/log_service.dart test/services/log_service_test.dart
git commit -m "chore: expose profile startup logs"
```

Expected: commit contains only LogService and its focused test.

## Task 6: Build, Install, and Verify the Icon Launch on the iPhone

**Files:**
- Use: `scripts/ios_icon_launch_dev.sh`
- Update: `$RUN_DIR/summary.md`
- Update: `$RUN_DIR/artifacts.json` through `scripts/evidence_pack.py`
- Modify: `docs/control/status-and-roadmap.md`

- [ ] **Step 1: Build and install the Profile app**

Run:

```bash
python3 scripts/evidence_pack.py run "$RUN_DIR" -- \
  scripts/ios_icon_launch_dev.sh
```

Expected:
- `xcodebuild` builds `Profile-iphoneos/Runner.app`.
- `devicectl device install app` installs the app.
- No "Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode" message is produced by this build path.

- [ ] **Step 2: Launch without Flutter tooling**

First test the actual user workflow: unlock the iPhone and tap the HydraCam icon.

Then run a repeatable command launch without Flutter attachment:

```bash
python3 scripts/evidence_pack.py run "$RUN_DIR" -- \
  xcrun devicectl device process launch \
    --device AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A \
    --terminate-existing \
    com.vectorblanco.hydracam.dev
```

Expected:
- App foregrounds from the installed icon build.
- HydraCam reaches the expected first functional screen.
- The Flutter Debug tooling-only message does not appear.

- [ ] **Step 3: Capture real-device visual evidence**

Record a short video of the physical iPhone showing:

1. HydraCam icon on the Home Screen.
2. Tap on the icon.
3. App opens to the functional HydraCam screen.
4. If permission dialogs appear, accept them and continue until the first functional screen is visible.

Save the file as:

```text
$RUN_DIR/video/iphone-profile-icon-launch.mov
```

If a screenshot is available through Xcode Devices, QuickTime, or another reliable capture path, save it as:

```text
$RUN_DIR/screenshots/iphone-profile-icon-launch.png
```

Expected: the evidence pack has at least one video and one screenshot or a documented screenshot blocker.

- [ ] **Step 4: Capture launch command output or device logs**

Run the command launch with devicectl log output:

```bash
xcrun devicectl device process launch \
  --device AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A \
  --terminate-existing \
  --json-output "$RUN_DIR/device-logs/devicectl-launch.json" \
  --log-output "$RUN_DIR/device-logs/devicectl-launch.log" \
  com.vectorblanco.hydracam.dev
```

Expected:
- `device-logs/devicectl-launch.json` exists.
- `device-logs/devicectl-launch.log` exists.
- If Profile developer logs are visible, they show startup markers such as permission request, device ID, navigation decision, and `SlaveScreen` or master fallback logs.

- [ ] **Step 5: Update roadmap status with evidence path**

In `docs/control/status-and-roadmap.md`, keep the iOS physical-device row tied
to current evidence. As of 2026-06-07, the broad white-screen blocker is
superseded; use one of these narrower outcomes after profile/release evidence:

Passed:

```markdown
| iOS physical device | Partially unblocked | Debug runs through Flutter tooling only, as expected. A Profile build now launches from the Home Screen icon on a physical iPhone; see `logs/verification-runs/<run-dir>/`. Full release readiness still requires two-device capture smoke testing and store-signing validation. |
```

Failed:

```markdown
| iOS physical device | Blocked | Debug runs through Flutter tooling, but the Profile icon-launch build still fails on physical iPhone; see `logs/verification-runs/<run-dir>/` for the current failure evidence. |
```

Blocked:

```markdown
| iOS physical device | Blocked | Physical iPhone icon-launch validation could not complete because signing, device pairing, or hardware access was unavailable; see `logs/verification-runs/<run-dir>/`. |
```

Expected: the status row no longer conflates Debug tooling behavior with standalone icon launch.

- [ ] **Step 6: Finalize and validate the evidence pack**

For pass:

```bash
python3 scripts/evidence_pack.py finalize "$RUN_DIR" \
  --status passed \
  --note "Profile build installed and launched from the iPhone icon without Flutter tooling."
python3 scripts/evidence_pack.py check "$RUN_DIR"
```

For failure:

```bash
python3 scripts/evidence_pack.py finalize "$RUN_DIR" \
  --status failed \
  --note "Profile icon launch still failed; see video and device logs."
python3 scripts/evidence_pack.py check "$RUN_DIR"
```

Expected: `scripts/evidence_pack.py check` prints `Evidence pack valid: <run-dir>`.

- [ ] **Step 7: Commit docs and evidence disposition**

Run:

```bash
git add docs/control/status-and-roadmap.md "$RUN_DIR"
git commit -m "docs: record iOS icon launch verification"
```

Expected: commit includes the final status row and complete evidence pack. If the evidence pack contains large videos that should not be committed, move them to an approved external artifact location and commit only `summary.md`, `commands.log`, `artifacts.json`, and paths/checksums.

## Final Acceptance

- `git status -sb` was run before edits and before final commit.
- Debug remains documented as Flutter tooling or Xcode only.
- `ios/Runner/Info.plist` points to `$(PRODUCT_MODULE_NAME).SceneDelegate`.
- The app provides a `SceneDelegate` class.
- `scripts/ios_icon_launch_dev.sh` builds and installs Profile, not Debug.
- `fastlane ios device` no longer implies Debug is the icon-launchable physical-device path.
- `flutter analyze --no-pub` passes.
- `flutter test --no-pub test/services/log_service_test.dart test/platform_setup_test.dart` passes.
- Physical iPhone evidence proves either:
  - pass: Profile icon launch reaches the first functional HydraCam screen, or
  - fail/block: the current blocker is recorded with video/logs and exact commands.
- `docs/control/status-and-roadmap.md` reflects the verified outcome, not the old broad white-screen note.

## Rollback

- If the SceneDelegate change breaks `flutter run`, revert the Task 2 commit only and compare against a fresh `flutter create --platforms=ios` template before retrying.
- If Profile signing fails but Debug still works, keep the native launch-host fix and adjust only `IOS_DEVELOPMENT_TEAM`, `IOS_BUNDLE_ID`, or Apple developer account membership.
- If Profile starts but app logic fails after launch, do not call this an iOS icon-launch failure. Open a separate evidence run for the app logic issue, using the current video/log proof as baseline.

## Self-Review

- Spec coverage: The plan addresses the user's exact symptom by separating Flutter Debug tooling behavior from standalone icon launch, then adding a Profile install path and hardware evidence.
- Placeholder scan: No TBD/TODO/fill-in placeholders remain. The only dynamic value is `<run-dir>`, produced by `scripts/evidence_pack.py start`.
- Type consistency: `RUN_DIR`, `IOS_XCODE_DESTINATION_ID`, `IOS_DEVICE`, `IOS_DEVELOPMENT_TEAM`, and `IOS_BUNDLE_ID` are used consistently across commands and script code.
