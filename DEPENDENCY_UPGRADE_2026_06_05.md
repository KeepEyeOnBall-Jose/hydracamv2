# Dependency Upgrade Notes - 2026-06-05

## Toolchain

- Flutter: 3.44.1 stable
- Dart: 3.12.1
- Xcode: 26.5
- Android JDK: OpenJDK 17.0.19 via `flutter config --jdk-dir`
- Android Gradle Plugin: 8.7.3
- Gradle wrapper: 8.10.2
- Android compile/target SDK: 35
- Android NDK: 27.0.12077973
- Android min SDK: 24, because Flutter 3.44's Gradle extension now sets API 24 as the minimum supported Android API.
- CocoaPods: 1.16.2 in `ios/Podfile.lock`; the local `pod` executable currently hangs before printing a version.

## Dependency Result

Low-risk dependencies were upgraded to current passing versions where they did not force the Android SDK 36 toolchain path:

- `cupertino_icons` 1.0.9
- `permission_handler` 12.0.3
- `uuid` 4.5.3
- `mocktail` 1.0.5
- `flutter_lints` 6.0.0
- `flutter_appauth` 12.0.1

The following packages are intentionally pinned below latest because the latest resolvable versions failed the conservative Android validation path with AGP 8.7.3, Gradle 8.10.2, SDK 35, and NDK 27:

- `camera` 0.11.4
- `connectivity_plus` 7.0.0
- `device_info_plus` 12.4.0
- `network_info_plus` 7.0.0
- `package_info_plus` 8.3.1
- `photo_manager` 3.7.1
- `shared_preferences` 2.5.3
- `video_player` 2.10.1
- `wakelock_plus` 1.3.3

The latest path-provider platform packages are also overridden:

- `path_provider_android` 2.2.19
- `path_provider_foundation` 2.4.2

## Failed Latest-Version Checks

- `path_provider_android` 2.3.1 and `path_provider_foundation` 2.6.0 pulled in the native hook/JNI/objective-c package stack (`code_assets`, `hooks`, `jni`, `jni_flutter`, `objective_c`, `record_use`, and related packages). With those latest platform packages resolved, `timeout 25 flutter test test/platform_setup_test.dart -r expanded` timed out before loading the test.
- `camera` 0.12.0+1 and the latest platform/media/info plugin set failed `flutter build apk --debug` at `:app:checkDebugAarMetadata`. AndroidX CameraX 1.6.0 and AndroidX Core 1.18.0 require compile SDK 36 and Android Gradle Plugin 8.9.1 or newer. This is the separate SDK 36/toolchain experiment path, not the conservative main path.
- The iOS simulator build is blocked by local CocoaPods startup. `pod --version` and `pod install --verbose` both hang in `/opt/homebrew/Cellar/cocoapods/1.16.2_1/libexec/bin/pod`.

## Validation

Passing checks:

- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
- `flutter build appbundle --release`
- `git diff --check`

Blocked checks:

- `flutter build ios --simulator`: Xcode package resolution succeeds when run directly against `ios/Runner.xcworkspace`, but the Flutter build then blocks in `pod install --verbose`.
- Emulator/simulator smoke checks were not run because this update focused on build/test validation and the iOS build is blocked before an app bundle is produced.

## Local Environment Notes

- Android builds required temporarily moving two broken Android Studio bundles out of `/Applications` because Flutter scans all Android Studio app bundles and hangs on `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java -version`. The bundles were restored after validation.
- Flutter is configured to use `/Applications/Android Studio 3.app` for Android Studio discovery and OpenJDK 17 for Android builds.
- The successful Android builds still emit future-facing Flutter warnings that AGP 8.7.3, Gradle 8.10.2, Kotlin 2.1.0, and compile SDK 35 are nearing or below future Flutter/plugin support floors. They are warnings on this conservative path, not current build failures.
