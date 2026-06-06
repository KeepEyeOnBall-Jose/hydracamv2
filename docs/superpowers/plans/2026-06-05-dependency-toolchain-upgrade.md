# Dependency and Toolchain Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring HydraCam to current stable Flutter, current problem-minimized package versions, and compatible Android/iOS toolchains without mixing dependency changes with unrelated app fixes.

**Architecture:** Treat the upgrade as a sequence of rollback-friendly checkpoints: baseline, Flutter SDK, lockfile-only packages, high-risk plugin groups, Android/iOS native build layers, then device validation. Keep the existing master/slave app architecture unchanged and preserve the known iOS physical-device white-screen issue as a separate diagnosis unless the upgrade directly changes it.

**Tech Stack:** Flutter 3.44 stable target, Dart SDK bundled with Flutter, pub.dev packages, Android Gradle Plugin/Kotlin/Gradle/JDK, CocoaPods, Xcode, iOS pods, Flutter analyzer and tests.

---

## Current Evidence Snapshot

- Local Flutter is `3.29.3` with Dart `3.7.2`.
- Official Flutter docs on 2026-06-05 identify Flutter `3.44` as the current stable series and recommend the stable channel for production app releases.
- `pubspec.yaml` declares Dart SDK `>=3.0.0 <4.0.0`.
- `flutter pub outdated` reports 13 locked packages can upgrade with `flutter pub upgrade`, and 3 direct constraints are older than a resolvable version.
- Current Android config: AGP `8.7.3`, Kotlin plugin `2.1.0`, Gradle wrapper `8.10.2`, `compileSdk = 35`, `targetSdk = 35`, `ndkVersion = "27.0.12077973"`, Java target `17`.
- Android Developers docs say AGP `8.7` supports max API `35`, minimum Gradle `8.9`, default NDK `27.0.12077973`, and JDK `17`.
- Android Developers docs list AGP `9.2.0` as current, with max API `36.1`, Gradle `9.4.1`, NDK `28.2.13676358`, and JDK `17`.
- Shell Java is currently Temurin `26.0.1`; do not use that as the Android build JDK for this upgrade.
- Current iOS config: `platform :ios, '13.0'`, CocoaPods `1.16.2`, Xcode `26.5`.
- `flutter doctor -v` hung during planning and was killed; rerun it after SDK/toolchain setup before any build work.

## Target Policy

- Use Flutter stable only, not beta or main.
- Prefer latest package versions that pass solver, analyzer, tests, simulator launch, Android debug build, and iOS simulator build.
- For camera, media, permissions, networking, Auth0, and native-platform packages, upgrade in small groups and keep the previous passing checkpoint available.
- Do not reintroduce `gallery_saver` or `battery_info`; both are already documented as incompatible with the current Android Gradle direction.
- Do not change application behavior during this upgrade unless required by compiler, analyzer, or plugin API changes.

## Candidate Direct Package Targets

These are the package targets observed from `flutter pub outdated` on 2026-06-05. Re-check them at execution time because pub.dev may have moved.

| Package | Current lock | First target | Later target after Flutter SDK upgrade |
| --- | ---: | ---: | ---: |
| `camera` | `0.11.2+1` | `0.11.2+1` | `0.12.0+1` |
| `connectivity_plus` | `7.0.0` | `7.1.1` | `7.1.1` |
| `cupertino_icons` | `1.0.8` | `1.0.8` | `1.0.9` |
| `device_info_plus` | `12.2.0` | `12.4.0` | `13.1.0` |
| `flutter_appauth` | `11.0.0` | `11.0.0` | `12.0.1` |
| `network_info_plus` | `7.0.0` | `7.0.0` | `8.1.0` |
| `package_info_plus` | `8.3.1` | `9.0.1` | `10.1.0` |
| `permission_handler` | `12.0.1` | `12.0.3` | `12.0.3` |
| `photo_manager` | `3.7.1` | `3.9.0` | `3.9.0` |
| `shared_preferences` | `2.5.3` | `2.5.3` | `2.5.5` |
| `uuid` | `4.5.2` | `4.5.3` | `4.5.3` |
| `video_player` | `2.10.1` | `2.10.1` | `2.11.1` |
| `wakelock_plus` | `1.3.3` | `1.4.0` | `1.6.1` |
| `flutter_lints` | `5.0.0` | `5.0.0` | `6.0.0` |
| `mocktail` | `1.0.4` | `1.0.5` | `1.0.5` |

## Files Planned for Modification

- Modify: `pubspec.yaml` for direct dependency constraints and possibly Dart SDK lower bound after the Flutter SDK target is confirmed.
- Modify: `pubspec.lock` through `flutter pub get` or `flutter pub upgrade`.
- Modify: `android/settings.gradle` only when moving AGP/Kotlin versions.
- Modify: `android/gradle/wrapper/gradle-wrapper.properties` only when moving Gradle.
- Modify: `android/app/build.gradle` only when moving `compileSdk`, `targetSdk`, `ndkVersion`, or Java build settings.
- Modify: `ios/Podfile` only if plugin release notes require a higher deployment target or changed permission macros.
- Modify: `ios/Podfile.lock` through `pod install` or Flutter iOS build.
- Modify: `analysis_options.yaml` only if `flutter_lints` 6 introduces new intended lint configuration changes.
- Create: `logs/dependency-upgrade/` for command outputs that are useful to preserve.
- Create or modify: `DISTRIBUTION_RUNBOOK.md` only if final build requirements or release commands change.

## Task 1: Baseline and Isolation

**Files:**
- Read: `pubspec.yaml`
- Read: `pubspec.lock`
- Read: `android/settings.gradle`
- Read: `android/gradle/wrapper/gradle-wrapper.properties`
- Read: `android/app/build.gradle`
- Read: `ios/Podfile`
- Create: `logs/dependency-upgrade/`

- [ ] **Step 1: Confirm the dirty worktree**

Run:

```bash
git status -sb
```

Expected: current unrelated local changes are visible. Do not stage or revert them.

- [ ] **Step 2: Create an isolated branch or worktree**

Run from the main checkout:

```bash
git worktree add .worktrees/codex/dependency-toolchain-upgrade -b codex/dependency-toolchain-upgrade
```

Expected: a new worktree exists under `.worktrees/codex/dependency-toolchain-upgrade`.

- [ ] **Step 3: Record the current dependency and toolchain state**

Run inside the isolated worktree:

```bash
mkdir -p logs/dependency-upgrade
flutter --version | tee logs/dependency-upgrade/00-flutter-version.txt
dart --version 2>&1 | tee logs/dependency-upgrade/00-dart-version.txt
flutter pub outdated | tee logs/dependency-upgrade/00-pub-outdated.txt
pod --version | tee logs/dependency-upgrade/00-pod-version.txt
xcodebuild -version | tee logs/dependency-upgrade/00-xcode-version.txt
java -version 2>&1 | tee logs/dependency-upgrade/00-java-version.txt
cd android
./gradlew --version | tee ../logs/dependency-upgrade/00-gradle-version.txt
cd ..
```

Expected: logs contain the same shape of facts listed in the snapshot section.

- [ ] **Step 4: Establish the pre-upgrade test baseline**

Run:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator
```

Expected: every passing/failing command is recorded. If an existing failure appears, save the full output under `logs/dependency-upgrade/01-baseline-<command>.txt` and do not treat it as caused by the upgrade.

- [ ] **Step 5: Commit only the baseline logs when useful**

Run:

```bash
git add logs/dependency-upgrade
git commit -m "chore: capture dependency upgrade baseline"
```

Expected: commit succeeds only if logs are useful and accepted for repository history. If logs are not intended for source control, skip the commit and keep them local.

## Task 2: Flutter SDK Upgrade

**Files:**
- Modify: toolchain outside the repo, or project-local Flutter version manager config if one is introduced.
- Read: `pubspec.yaml`
- Modify: `pubspec.lock` through `flutter pub get`

- [ ] **Step 1: Upgrade to stable Flutter**

Run:

```bash
flutter channel stable
flutter upgrade --verify-only
flutter upgrade
flutter --version
```

Expected: Flutter reports the current stable channel, targeting Flutter `3.44.x` as of 2026-06-05.

- [ ] **Step 2: Rerun doctor after the SDK upgrade**

Run:

```bash
flutter doctor -v | tee logs/dependency-upgrade/02-flutter-doctor-after-sdk.txt
```

Expected: `flutter doctor -v` completes. Resolve missing Android SDK, Xcode, CocoaPods, or license issues before continuing.

- [ ] **Step 3: Refresh generated Flutter metadata**

Run:

```bash
flutter pub get
```

Expected: `pubspec.lock` may change only because the Flutter/Dart SDK changed.

- [ ] **Step 4: Validate SDK-only impact**

Run:

```bash
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator
```

Expected: the app still analyzes, tests, and builds. Fix only SDK-driven compile/analyzer failures before changing package versions.

- [ ] **Step 5: Commit the SDK checkpoint**

Run:

```bash
git add pubspec.lock logs/dependency-upgrade
git commit -m "chore: upgrade Flutter SDK baseline"
```

Expected: the commit contains SDK/lockfile effects and logs only.

## Task 3: Low-Risk Lockfile Upgrade

**Files:**
- Modify: `pubspec.lock`

- [ ] **Step 1: Upgrade within existing constraints**

Run:

```bash
flutter pub upgrade
flutter pub outdated | tee logs/dependency-upgrade/03-pub-outdated-after-lock-upgrade.txt
```

Expected: lockfile moves to latest versions allowed by the current `pubspec.yaml`.

- [ ] **Step 2: Validate lockfile-only changes**

Run:

```bash
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator
```

Expected: no new failures. If a failure appears, use `git diff pubspec.lock` to identify the upgraded package group and pin the smallest failing package back to the previous version.

- [ ] **Step 3: Commit lockfile upgrade**

Run:

```bash
git add pubspec.lock logs/dependency-upgrade
git commit -m "chore: refresh dependency lockfile"
```

Expected: commit contains `pubspec.lock` and relevant logs.

## Task 4: Dart-Only and Test Dependency Constraints

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `analysis_options.yaml` only if lint configuration must be adjusted.

- [ ] **Step 1: Update low-risk direct constraints**

Edit `pubspec.yaml` direct dependencies to these target constraints:

```yaml
cupertino_icons: ^1.0.9
permission_handler: ^12.0.3
photo_manager: ^3.9.0
uuid: ^4.5.3
mocktail: ^1.0.5
flutter_lints: ^6.0.0
```

- [ ] **Step 2: Resolve packages**

Run:

```bash
flutter pub get
flutter pub outdated | tee logs/dependency-upgrade/04-pub-outdated-after-low-risk.txt
```

Expected: solver succeeds and these packages are no longer behind their latest compatible versions.

- [ ] **Step 3: Validate low-risk package changes**

Run:

```bash
flutter analyze
flutter test
```

Expected: analyzer and tests pass. If new lint failures appear from `flutter_lints` 6, fix the code when the lint points to a real issue; otherwise add one explicit rule override in `analysis_options.yaml` with a one-line reason.

- [ ] **Step 4: Commit low-risk constraints**

Run:

```bash
git add pubspec.yaml pubspec.lock analysis_options.yaml logs/dependency-upgrade
git commit -m "chore: update low-risk Dart dependencies"
```

Expected: commit contains only package metadata, lint config if changed, and logs.

## Task 5: Device and Platform Info Plugins

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Review: `lib/services/permission_service.dart`
- Review: `lib/services/storage_service.dart`
- Review: `lib/services/battery_service.dart`
- Review: `lib/screens/camera_selection_screen.dart`

- [ ] **Step 1: Update device and connectivity constraints**

Edit `pubspec.yaml` direct dependencies:

```yaml
connectivity_plus: ^7.1.1
device_info_plus: ^13.1.0
network_info_plus: ^8.1.0
package_info_plus: ^10.1.0
wakelock_plus: ^1.6.1
```

- [ ] **Step 2: Resolve packages**

Run:

```bash
flutter pub get
```

Expected: solver succeeds. If `device_info_plus`, `package_info_plus`, or `network_info_plus` requires a higher Dart lower bound, raise `environment.sdk` to the Dart version bundled with the upgraded Flutter stable SDK and rerun `flutter pub get`.

- [ ] **Step 3: Compile-check platform API usages**

Run:

```bash
flutter analyze
flutter test test/platform_setup_test.dart
flutter test test/platform/platform_behavior_test.dart
flutter test test/services/battery_service_test.dart
flutter test test/services/storage_service_test.dart
```

Expected: platform service tests pass. Update only compile errors caused by package API changes.

- [ ] **Step 4: Build-check Android and iOS**

Run:

```bash
flutter build apk --debug
flutter build ios --simulator
```

Expected: both builds pass.

- [ ] **Step 5: Commit platform info plugins**

Run:

```bash
git add pubspec.yaml pubspec.lock lib/services/permission_service.dart lib/services/storage_service.dart lib/services/battery_service.dart lib/screens/camera_selection_screen.dart logs/dependency-upgrade
git commit -m "chore: update platform information plugins"
```

Expected: commit includes only files actually changed.

## Task 6: Camera and Media Plugins

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Review: `lib/services/camera_service_singleton.dart`
- Review: `lib/widgets/add_gallery_media_button.dart`
- Review: `lib/master/master_screen.dart`
- Review: `lib/slave/` if camera command compile errors point there.
- Test: `test/services/camera_service_test.dart`
- Test: `test/camera_singleton_initialization_test.dart`

- [ ] **Step 1: Update camera and video constraints**

Edit `pubspec.yaml` direct dependencies:

```yaml
camera: ^0.12.0+1
video_player: ^2.11.1
```

- [ ] **Step 2: Resolve packages**

Run:

```bash
flutter pub get
```

Expected: solver succeeds and camera platform interface packages update.

- [ ] **Step 3: Fix compile errors only**

Run:

```bash
flutter analyze
```

Expected: if camera API signatures changed, update `camera_service_singleton.dart` and directly related call sites while preserving existing behavior.

- [ ] **Step 4: Validate camera tests**

Run:

```bash
flutter test test/services/camera_service_test.dart
flutter test test/camera_singleton_initialization_test.dart
flutter test test/widget_test.dart
```

Expected: camera service and widget tests pass.

- [ ] **Step 5: Validate on simulator/emulator**

Run:

```bash
flutter build apk --debug
flutter build ios --simulator
```

Expected: both builds pass. Launch manually on one Android emulator and one iOS simulator if available, and verify the app does not regress before starting a session.

- [ ] **Step 6: Commit media plugin upgrade**

Run:

```bash
git add pubspec.yaml pubspec.lock lib/services/camera_service_singleton.dart lib/widgets/add_gallery_media_button.dart lib/master/master_screen.dart lib/slave logs/dependency-upgrade
git commit -m "chore: update camera and media plugins"
```

Expected: commit includes only files actually changed.

## Task 7: Auth and Shared Preferences Plugins

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Review: `lib/services/auth0_service.dart`
- Review: `lib/services/settings_service.dart`

- [ ] **Step 1: Update auth and preferences constraints**

Edit `pubspec.yaml` direct dependencies:

```yaml
flutter_appauth: ^12.0.1
shared_preferences: ^2.5.5
```

- [ ] **Step 2: Resolve and analyze**

Run:

```bash
flutter pub get
flutter analyze
```

Expected: solver and analyzer pass.

- [ ] **Step 3: Validate auth/settings-adjacent tests**

Run:

```bash
flutter test test/services/session_manager_test.dart
flutter test test/platform_setup_test.dart
flutter build apk --debug
flutter build ios --simulator
```

Expected: no regression in session or platform startup behavior.

- [ ] **Step 4: Commit auth/preferences upgrade**

Run:

```bash
git add pubspec.yaml pubspec.lock lib/services/auth0_service.dart lib/services/settings_service.dart logs/dependency-upgrade
git commit -m "chore: update auth and preferences plugins"
```

Expected: commit includes only files actually changed.

## Task 8: Android Native Toolchain Decision

**Files:**
- Modify: `android/settings.gradle`
- Modify: `android/gradle/wrapper/gradle-wrapper.properties`
- Modify: `android/app/build.gradle`
- Modify: `android/gradle.properties` if a project JDK path is introduced.
- Modify: `DISTRIBUTION_RUNBOOK.md` if build prerequisites change.

- [ ] **Step 1: Pin the Android build JDK to 17**

Configure the shell or IDE to use JDK 17 for Android builds. Preferred local shell command:

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
java -version
```

Expected: `java -version` reports a Java 17 runtime for the build session.

- [ ] **Step 2: Validate current AGP 8.7.3 stack first**

Run:

```bash
flutter build apk --debug
flutter build appbundle --release
```

Expected: current AGP `8.7.3`, Gradle `8.10.2`, API `35`, and NDK `27.0.12077973` still build. Keep this stack if the goal is minimum-risk release readiness.

- [ ] **Step 3: Create a separate AGP 9.2 experiment branch**

Run:

```bash
git checkout -b codex/android-agp-9-experiment
```

Expected: Android native tooling experiment is isolated from the package upgrade branch.

- [ ] **Step 4: Update Android toolchain only in the experiment**

Edit `android/settings.gradle`:

```gradle
id "com.android.application" version "9.2.0" apply false
id "org.jetbrains.kotlin.android" version "2.2.10" apply false
```

Edit `android/gradle/wrapper/gradle-wrapper.properties`:

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-9.4.1-all.zip
```

Edit `android/app/build.gradle`:

```gradle
compileSdk = 36
ndkVersion = "28.2.13676358"
targetSdk = 36
```

- [ ] **Step 5: Validate AGP 9.2 experiment**

Run:

```bash
flutter clean
flutter pub get
flutter build apk --debug
flutter build appbundle --release
```

Expected: Android builds pass. If Flutter Gradle integration or plugins fail under AGP 9.2, abandon this experiment for the release branch and keep AGP `8.7.3` until Flutter templates or plugin release notes confirm compatibility.

- [ ] **Step 6: Commit or discard Android native toolchain experiment**

Run after successful validation:

```bash
git add android/settings.gradle android/gradle/wrapper/gradle-wrapper.properties android/app/build.gradle DISTRIBUTION_RUNBOOK.md
git commit -m "chore: update Android build toolchain"
```

Expected: commit is kept only when both debug APK and release AAB build pass.

## Task 9: iOS Pods and Deployment Target Check

**Files:**
- Modify: `ios/Podfile`
- Modify: `ios/Podfile.lock`
- Review: `ios/Runner/Info.plist`
- Review: `DISTRIBUTION_RUNBOOK.md`

- [ ] **Step 1: Reinstall pods after package upgrades**

Run:

```bash
cd ios
pod install
cd ..
```

Expected: `ios/Podfile.lock` updates cleanly.

- [ ] **Step 2: Build iOS simulator**

Run:

```bash
flutter build ios --simulator
```

Expected: simulator build passes with iOS platform `13.0`.

- [ ] **Step 3: Check whether package release notes require iOS target changes**

Review current package release notes for `camera`, `photo_manager`, `flutter_appauth`, `permission_handler`, `network_info_plus`, and `video_player`. If any package requires a deployment target higher than iOS 13, update `ios/Podfile` to the smallest required deployment target and rerun `pod install`.

- [ ] **Step 4: Validate Info.plist permissions**

Confirm `ios/Runner/Info.plist` still contains camera, microphone, photo library, location, and Auth0 redirect entries needed by the upgraded plugins.

- [ ] **Step 5: Commit iOS pod changes**

Run:

```bash
git add ios/Podfile ios/Podfile.lock ios/Runner/Info.plist DISTRIBUTION_RUNBOOK.md
git commit -m "chore: refresh iOS pods after dependency upgrade"
```

Expected: commit contains only changed iOS build metadata and docs.

## Task 10: Final Regression Matrix

**Files:**
- Modify: `DISTRIBUTION_RUNBOOK.md`
- Modify: `TESTING_SUMMARY.md` or `TEST_PLAN_MULTI_DEVICE.md` if final validation steps changed.

- [ ] **Step 1: Run full static and unit test suite**

Run:

```bash
flutter analyze
flutter test
```

Expected: analyzer and tests pass.

- [ ] **Step 2: Run platform builds**

Run:

```bash
flutter build apk --debug
flutter build appbundle --release
flutter build ios --simulator
```

Expected: Android debug APK, Android release AAB, and iOS simulator build pass.

- [ ] **Step 3: Run app smoke checks**

Run or manually verify:

```bash
flutter run -d <android-emulator-id>
flutter run -d <ios-simulator-id>
```

Expected: app launches, camera permission flow appears, camera preview initializes, session start screen is reachable, and no new startup white screen appears on simulator/emulator.

- [ ] **Step 4: Run physical device checks when devices are available**

Run:

```bash
flutter run -d <physical-ios-device-id>
flutter run -d <physical-android-device-id>
```

Expected: Android launches. iOS physical-device result is recorded separately because a white-screen issue pre-exists the upgrade.

- [ ] **Step 5: Update docs with final supported versions**

Update `DISTRIBUTION_RUNBOOK.md` with the final verified versions:

```markdown
## Verified Build Stack

- Flutter: 3.44.x stable
- Dart: bundled with Flutter 3.44.x
- Android Gradle Plugin: 8.7.3 unless AGP 9.2 experiment passes
- Gradle: 8.10.2 unless AGP 9.2 experiment passes
- Android JDK: 17
- Android compileSdk/targetSdk: 35 unless AGP 9.2 experiment passes
- iOS deployment target: 13.0 unless plugin release notes require a higher target
- CocoaPods: 1.16.2
- Xcode: 26.5
```

- [ ] **Step 6: Commit final docs**

Run:

```bash
git add DISTRIBUTION_RUNBOOK.md TESTING_SUMMARY.md TEST_PLAN_MULTI_DEVICE.md logs/dependency-upgrade
git commit -m "docs: record verified dependency upgrade stack"
```

Expected: commit contains validation evidence and updated docs only.

## Completion Criteria

- `flutter --version` reports stable Flutter `3.44.x` or newer stable verified on the day of execution.
- `flutter pub outdated` shows no low-risk direct dependency updates remaining, and any intentionally pinned packages are documented with the failing command that justified the pin.
- `flutter analyze` passes.
- `flutter test` passes.
- `flutter build apk --debug` passes.
- `flutter build appbundle --release` passes with the intended signing fallback or release signing setup.
- `flutter build ios --simulator` passes.
- Android emulator launch works.
- iOS simulator launch works.
- Physical-device validation result is recorded, with the known iOS white-screen issue kept separate from dependency upgrade regressions.

## Rollback Strategy

- Each task ends in a commit so a failing package group can be reverted with `git revert <commit>`.
- Keep the AGP 9.2 experiment separate from the main package upgrade path.
- If a latest package breaks behavior, pin the previous passing version in `pubspec.yaml`, record the command output under `logs/dependency-upgrade/`, and proceed with the rest of the upgrade.
- Do not merge the upgrade branch into release work until the final regression matrix passes.

## Self-Review

- Spec coverage: The plan covers Flutter SDK, Dart packages, Android Gradle/Kotlin/Gradle/JDK/SDK/NDK, iOS pods/deployment target, validation, docs, and rollback.
- Placeholder scan: The plan avoids open-ended placeholders and records exact commands, files, and candidate version targets.
- Risk controls: The highest-risk changes are isolated: Flutter SDK first, camera/media plugins in their own task, Auth0 in its own task, and AGP 9.2 in a separate experiment branch.
