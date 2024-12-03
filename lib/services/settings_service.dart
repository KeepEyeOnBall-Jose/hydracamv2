import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

class SettingsService {

  static const String _masterShouldRecordKey = 'masterShouldRecord';          // Whether or not master should also take pics/videos
  static const String _cameraQualityKey = 'cameraQuality';                    // Use max, mid or minimum quality available for the camera
  static const String _deleteLocalAfterUploadKey = 'deleteLocalAfterUpload';  // Choose if delete or not the media after uploading
  static const String _autoUploadMaterialsKey = 'autoUploadMaterials';        // Choose if automatically upload materials or not
  static const String _autoplayVideoOnMasterKey = 'autoplayVideoOnMaster';    // Toggle auto video play in master device after recording
  static const String _timerDurationKey = 'timerDuration';                    // Key for the timer duration setting
  static const String _screenAutoOffKey = 'screenAutoOff';                    // Key for auto screen off setting

  /// Retrieve the current value for "masterShouldRecord"
  static Future<bool> getMasterShouldRecord() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_masterShouldRecordKey) ?? true; // Default to true
  }

  /// Update the value for "masterShouldRecord"
  static Future<void> setMasterShouldRecord(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_masterShouldRecordKey, value);

    LogService.instance.registerLog("Update massterShouldRecord value to $value");
  }

  /// Retrieve the current camera quality setting
  static Future<String> getCameraQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cameraQualityKey) ?? 'high'; // Default to 'high'
  }

  /// Update the camera quality setting
  static Future<void> setCameraQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cameraQualityKey, quality);

    LogService.instance.registerLog("Update Camera Quality value to $quality");
  }

  /// Retrieve the current value for "deleteLocalAfterUpload"
  static Future<bool> getDeleteLocalAfterUpload() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deleteLocalAfterUploadKey) ?? false; // Default to false
  }

  /// Update the value for "deleteLocalAfterUpload"
  static Future<void> setDeleteLocalAfterUpload(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deleteLocalAfterUploadKey, value);

    LogService.instance.registerLog("Update delete local file after upload value to $value");
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
    LogService.instance.registerLog("Update autoUploadMaterials value to $value");
  }

  /// Retrieve the current value for "autoplayVideoOnMaster".
  static Future<bool> getAutoplayVideoOnMaster() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoplayVideoOnMasterKey) ?? false; // Default to false
  }

  /// Update the value for "autoplayVideoOnMaster".
  static Future<void> setAutoplayVideoOnMaster(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoplayVideoOnMasterKey, value);
    LogService.instance.registerLog("Updated autoplayVideoOnMaster value to $value");
  }

  /// Retrieve the current value for "timerDuration"
  static Future<int> getTimerDuration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_timerDurationKey) ?? 6; // Default to 5 seconds
  }

  /// Update the value for "timerDuration"
  static Future<void> setTimerDuration(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timerDurationKey, value);
    LogService.instance.registerLog("Updated timerDuration to $value seconds");
  }

  /// Retrieve the current value for "screenAutoOff"
  static Future<bool> getScreenAutoOff() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_screenAutoOffKey) ?? false; // Default to false (screen stays on)
  }

  /// Update the value for "screenAutoOff"
  static Future<void> setScreenAutoOff(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_screenAutoOffKey, value);
    LogService.instance.registerLog("Updated screenAutoOff to $value");
  }
}
