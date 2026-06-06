# Migration Notes - November 2025

> Historical migration snapshot. Current project status lives in
> `docs/control/status-and-roadmap.md`. Re-verify build and platform claims
> before relying on them.

## Summary
Successfully updated the HydraCam Flutter app to work with current Flutter/Dart versions and build on all supported platforms.

## Changes Made

### 1. SDK Updates
- **Dart SDK**: Updated from `>=2.19.6 <3.0.0` to `>=3.0.0 <4.0.0` (compatible with Flutter 3.29.3)

### 2. iOS Configuration
- **Deployment Target**: Updated from iOS 12.0 to iOS 13.0 in `ios/Podfile`
- **CocoaPods**: Successfully updated all iOS pods
- **Status**: ⚠️ Build works but has Xcode sandbox permission issues in some environments

### 3. macOS Configuration
- **Deployment Target**: Updated from macOS 10.14 to 10.15 in both `macos/Podfile` and `macos/Runner.xcodeproj/project.pbxproj`
- **CocoaPods**: Successfully updated all macOS pods
- **Status**: ✅ Builds successfully

### 4. Android Configuration
- **Gradle Plugin**: Updated from 8.3.2 to 8.7.3 in `android/settings.gradle`
- **Kotlin**: Updated from 1.9.22 to 2.1.0
- **NDK Version**: Updated to 27.0.12077973
- **Build Config**: Migrated to new Gradle plugin format (declarative syntax)
- **Status**: ✅ Builds successfully

### 5. Web Configuration
- **Status**: ✅ Builds successfully
- Minor warnings about deprecated FlutterLoader methods (not blocking)

### 6. Removed Incompatible Plugins

#### battery_info (^1.1.1)
- **Reason**: Incompatible with Android Gradle Plugin 8.7+ (missing namespace declaration)
- **Impact**: Battery monitoring temporarily disabled in `lib/services/battery_service.dart`
- **Recommendation**: Find alternative plugin or wait for update

#### gallery_saver (^2.3.2)
- **Reason**: Incompatible with Android Gradle Plugin 8.7+ (missing namespace declaration)
- **Impact**: Media is saved to app directory but NOT automatically saved to device gallery
- **Code Modified**:
  - `lib/services/camera_service.dart`
  - `lib/master/master_server.dart`
- **Recommendation**: Use `photo_manager` plugin (already in dependencies) to implement gallery saving

## Build Status

| Platform | Status | Notes |
|----------|--------|-------|
| Android  | ✅ Success | APK builds successfully |
| iOS      | ⚠️ Partial | Xcode sandbox issues in some environments |
| macOS    | ✅ Success | App builds successfully |
| Web      | ✅ Success | Builds with minor deprecation warnings |

## Testing Commands

```bash
# Android
flutter build apk --debug

# iOS (simulator)
flutter build ios --no-codesign --simulator

# macOS
flutter build macos --debug

# Web
flutter build web --debug
```

## Post-Migration Tasks

### High Priority
1. **Implement gallery saving**: Replace removed `gallery_saver` functionality using `photo_manager`
2. **Battery monitoring**: Find alternative to `battery_info` or implement platform-specific solution
3. **Test on physical devices**: Especially iOS - verify camera and media functionality

### Medium Priority
4. **Update dependencies**: Run `flutter pub outdated` and update packages within constraints
5. **iOS Sandbox**: Investigate and resolve Xcode sandbox permission issues
6. **Web Initialization**: Update `web/index.html` to use new FlutterLoader API

### Low Priority
7. **Consider updating**: Some packages have newer versions available (see pub outdated)
8. **Code review**: Check for any deprecated Flutter APIs in the codebase

## Known Issues

1. **Gallery saving disabled**: Media files are saved to app directories but not to device photo gallery
2. **Battery monitoring disabled**: Battery level warnings not functional
3. **iOS build sandbox**: May have permission issues in certain Xcode configurations

## Migration Compatibility

- **Flutter Version**: 3.29.3 (Dart 3.7.2)
- **Minimum SDK Versions**:
  - Android: minSdk 21
  - iOS: 13.0
  - macOS: 10.15
- **Compile SDK**: Android 35

## Additional Notes

- All core functionality (camera, video recording, WebSocket communication) should work
- The app structure and logic remain unchanged
- Only platform configuration and incompatible plugins were modified
- All commented-out code is marked with TODO for future implementation
