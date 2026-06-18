# Evidence Run: Flutter 3.44 platform dependency upgrade

- Source: docs/control/status-and-roadmap.md
- Slug: `flutter-3-44-platform-dependency-upgrade`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Flutter dependencies resolve under Flutter 3.44.1
- [x] Analyzer and full Flutter tests pass
- [x] Android release app bundle builds with upgraded AGP and dependencies
- [x] iOS and macOS platform builds either pass or document concrete blockers
- [x] Store readiness preflight no longer fails the Android URL-launcher pin after AGP upgrade

## Device Matrix

- No device proof was required for this platform/toolchain slice. Android proof
  is a signed release app bundle build; iOS proof is a no-codesign device build.

## Evidence

- `commands.log` records:
  - `flutter pub get`
  - `flutter analyze --no-pub`
  - `flutter test --no-pub`
  - Interrupted `flutter build appbundle --release` attempts where Flutter
    hung probing Android Studio's bundled JBR at `java -version`.
  - `flutter config --jdk-dir /Library/Java/JavaVirtualMachines/temurin-26.jdk/Contents/Home`.
  - Direct Gradle app bundle attempt with JDK 26, which failed plugin
    resolution on Java `26.0.1`.
  - Direct Gradle app bundle attempt with JDK 17, which passed:
    `env JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home android/gradlew -p android bundleRelease`.
  - `flutter build ios --release --no-codesign`, which passed and produced
    `build/ios/iphoneos/Runner.app`.
  - `flutter build macos`, which failed because the current dirty macOS project
    is no longer configured.
  - Store readiness local preflight with public URLs, which no longer fails the
    Android `url_launcher_android` pin and now fails only on missing iOS
    Distribution/App Store Connect signing credentials.
  - Scoped platform `git diff --check`, which passed.
- Android app bundle artifact after the successful Gradle build:
  `build/app/outputs/bundle/release/app-release.aab`, SHA-256
  `36678b653195b28e79fd6a459c469c92a62aae694b745dfe40306bcd70330464`.

## Result

- Final disposition: partial. The mobile platform/dependency upgrade is
  commit-ready for Android and iOS. The dirty macOS SPM/CocoaPods migration is
  not commit-ready and remains excluded until `flutter build macos` succeeds or
  the project is restored to the CocoaPods workspace flow.
