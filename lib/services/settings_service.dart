import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../models/camera_capture_settings.dart";
import "../models/capture_context_metadata.dart";
import "log_service.dart";

// ignore: avoid_classes_with_only_static_members
class SettingsService {
  static bool? _masterShouldRecordOverride;
  static int? _timerDurationOverride;

  static const String _masterShouldRecordKey =
      "masterShouldRecord"; // Whether or not master should also take pics/videos
  static const String _cameraQualityKey =
      "cameraQuality"; // Use max, mid or minimum quality available for the camera
  static const String _cameraLensPreferenceKey = "cameraLensPreference";
  static const String _selectedCameraNameKey = "selectedCameraName";
  static const String _videoCaptureProfileKey = "videoCaptureProfile";
  static const String _cameraPerspectiveIdKey = "cameraPerspectiveId";
  static const String _deleteLocalAfterUploadKey =
      "deleteLocalAfterUpload"; // Choose if delete or not the media after uploading
  static const String _autoUploadMaterialsKey =
      "autoUploadMaterials"; // Choose if automatically upload materials or not
  static const String _autoplayVideoOnMasterKey =
      "autoplayVideoOnMaster"; // Toggle auto video play in master device after recording
  static const String _autoRecordModeKey =
      "autograbadoMode"; // Legacy storage key for auto-record mode.
  static const String _timerDurationKey =
      "timerDuration"; // Key for the timer duration setting
  static const String _screenAutoOffKey =
      "screenAutoOff"; // Key for auto screen off setting
  static const String _flashForVideoAnnounceKey =
      "flashForVideoAnnounce"; // Key for flashing on start/stop recording
  static const String _localeOverrideKey =
      "localeOverride"; // Optional app language override.

  /// Retrieve the current value for "flashForVideoAnnounce".
  static Future<bool> getFlashForVideoAnnounce() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_flashForVideoAnnounceKey) ??
        false; // Default to false
  }

  /// Update the value for "flashForVideoAnnounce".
  static Future<void> setFlashForVideoAnnounce(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flashForVideoAnnounceKey, value);
    LogService.instance
        .registerLog("Updated flashForVideoAnnounce value to $value");
  }

  /// Retrieve the current value for "masterShouldRecord"
  static Future<bool> getMasterShouldRecord() async {
    if (_masterShouldRecordOverride != null) {
      return _masterShouldRecordOverride!;
    }
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getBool(_masterShouldRecordKey);
    if (storedValue != null) {
      return storedValue;
    }
    return defaultTargetPlatform != TargetPlatform.macOS;
  }

  /// Update the value for "masterShouldRecord"
  static Future<void> setMasterShouldRecord(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_masterShouldRecordKey, value);

    LogService.instance
        .registerLog("Update massterShouldRecord value to $value");
  }

  /// Retrieve the current camera quality setting
  static Future<String> getCameraQuality() async {
    final profile = await getVideoCaptureProfile();
    return _legacyQualityFromVideoCaptureProfile(profile);
  }

  /// Update the camera quality setting
  static Future<void> setCameraQuality(String quality) async {
    final profile = VideoCaptureProfile.fromLegacyCameraQuality(quality);
    await setVideoCaptureProfile(profile);

    LogService.instance
        .registerLog("Updated legacy camera quality value to $quality");
  }

  static Future<LensPreference> getCameraLensPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return LensPreference.fromStorageValue(
      prefs.getString(_cameraLensPreferenceKey),
    );
  }

  static Future<void> setCameraLensPreference(LensPreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cameraLensPreferenceKey, preference.storageValue);
    LogService.instance.registerLog(
        "Updated camera lens preference to ${preference.storageValue}");
  }

  static Future<String?> getSelectedCameraName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedCameraNameKey);
  }

  static Future<void> setSelectedCameraName(String cameraName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedCameraNameKey, cameraName);
    LogService.instance
        .registerLog("Updated selected camera name to $cameraName");
  }

  static Future<void> clearSelectedCameraName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedCameraNameKey);
    LogService.instance.registerLog("Cleared selected camera name");
  }

  static Future<VideoCaptureProfile> getVideoCaptureProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final storedProfile = prefs.getString(_videoCaptureProfileKey);
    if (storedProfile != null) {
      return VideoCaptureProfile.fromStorageValue(storedProfile);
    }

    final legacyQuality = prefs.getString(_cameraQualityKey);
    final migratedProfile =
        VideoCaptureProfile.fromLegacyCameraQuality(legacyQuality);
    if (legacyQuality != null) {
      await prefs.setString(
          _videoCaptureProfileKey, migratedProfile.storageValue);
      await prefs.remove(_cameraQualityKey);
      LogService.instance.registerLog(
          "Migrated legacy camera quality to ${migratedProfile.storageValue}");
    }
    return migratedProfile;
  }

  static Future<void> setVideoCaptureProfile(
      VideoCaptureProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_videoCaptureProfileKey, profile.storageValue);
    await prefs.remove(_cameraQualityKey);
    LogService.instance.registerLog(
        "Updated video capture profile to ${profile.storageValue}");
  }

  static String _legacyQualityFromVideoCaptureProfile(
      VideoCaptureProfile profile) {
    return switch (profile) {
      VideoCaptureProfile.dataSaver480p30 => "low",
      VideoCaptureProfile.compat720p30 => "medium",
      _ => "high",
    };
  }

  static Future<CameraPerspectiveMetadata> getCameraPerspective() async {
    final prefs = await SharedPreferences.getInstance();
    return CameraPerspectiveMetadata.fromId(
      prefs.getString(_cameraPerspectiveIdKey),
    );
  }

  static Future<void> setCameraPerspectiveId(String perspectiveId) async {
    final perspective = CameraPerspectiveMetadata.fromId(perspectiveId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cameraPerspectiveIdKey,
      perspective.cameraPerspectiveId,
    );
    LogService.instance.registerLog(
        "Updated camera perspective to ${perspective.cameraPerspectiveId}");
  }

  /// Retrieve the current value for "deleteLocalAfterUpload"
  static Future<bool> getDeleteLocalAfterUpload() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deleteLocalAfterUploadKey) ??
        false; // Default to false
  }

  /// Update the value for "deleteLocalAfterUpload"
  static Future<void> setDeleteLocalAfterUpload(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deleteLocalAfterUploadKey, value);

    LogService.instance
        .registerLog("Update delete local file after upload value to $value");
  }

  /// Retrieve the current value for "autoUploadMaterials"
  static Future<bool> getAutoUploadMaterials() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoUploadMaterialsKey) ?? true; // Default to true
  }

  /// Update the value for "autoUploadMaterials"
  static Future<void> setAutoUploadMaterials(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoUploadMaterialsKey, value);
    LogService.instance
        .registerLog("Update autoUploadMaterials value to $value");
  }

  /// Retrieve the current value for "autoplayVideoOnMaster".
  static Future<bool> getAutoplayVideoOnMaster() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoplayVideoOnMasterKey) ??
        false; // Default to false
  }

  /// Update the value for "autoplayVideoOnMaster".
  static Future<void> setAutoplayVideoOnMaster(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoplayVideoOnMasterKey, value);
    LogService.instance
        .registerLog("Updated autoplayVideoOnMaster value to $value");
  }

  /// Retrieve the current value for auto-record mode.
  static Future<bool> getAutoRecordMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoRecordModeKey) ?? false;
  }

  /// Update the value for auto-record mode.
  static Future<void> setAutoRecordMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoRecordModeKey, value);
    LogService.instance.registerLog("Updated autoRecordMode value to $value");
  }

  /// Retrieve the current value for "timerDuration"
  static Future<int> getTimerDuration() async {
    if (_timerDurationOverride != null) {
      return _timerDurationOverride!;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_timerDurationKey) ?? 3; // Default to 3 seconds
  }

  /// Update the value for "timerDuration"
  static Future<void> setTimerDuration(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timerDurationKey, value);
    LogService.instance.registerLog("Updated timerDuration to $value seconds");
  }

  static Future<String?> getLocaleOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_localeOverrideKey);
  }

  static Future<void> setLocaleOverride(String localeCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeOverrideKey, localeCode);
    LogService.instance.registerLog("Updated locale override to $localeCode");
  }

  static Future<void> clearLocaleOverride() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localeOverrideKey);
    LogService.instance.registerLog("Cleared locale override");
  }

  @visibleForTesting
  static void overrideMasterShouldRecord(bool value) {
    _masterShouldRecordOverride = value;
  }

  @visibleForTesting
  static void overrideTimerDuration(int value) {
    _timerDurationOverride = value;
  }

  @visibleForTesting
  static void clearTestOverrides() {
    _masterShouldRecordOverride = null;
    _timerDurationOverride = null;
  }

  /// Retrieve the current value for "screenAutoOff"
  static Future<bool> getScreenAutoOff() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_screenAutoOffKey) ??
        false; // Default to false (screen stays on)
  }

  /// Update the value for "screenAutoOff"
  static Future<void> setScreenAutoOff(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_screenAutoOffKey, value);
    LogService.instance.registerLog("Updated screenAutoOff to $value");
  }
}
