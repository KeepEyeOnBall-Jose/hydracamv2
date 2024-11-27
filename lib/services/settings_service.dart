import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _masterShouldRecordKey = 'masterShouldRecord';
  static const String _cameraQualityKey = 'cameraQuality';
  static const String _deleteLocalAfterUploadKey = 'deleteLocalAfterUpload';

  // Retrieve the current value for "masterShouldRecord"
  static Future<bool> getMasterShouldRecord() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_masterShouldRecordKey) ?? false; // Default to false
  }

  // Update the value for "masterShouldRecord"
  static Future<void> setMasterShouldRecord(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_masterShouldRecordKey, value);
  }

  // Retrieve the current camera quality setting
  static Future<String> getCameraQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cameraQualityKey) ?? 'high'; // Default to 'high'
  }

  // Update the camera quality setting
  static Future<void> setCameraQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cameraQualityKey, quality);
  }

  // Retrieve the current value for "deleteLocalAfterUpload"
  static Future<bool> getDeleteLocalAfterUpload() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deleteLocalAfterUploadKey) ?? false; // Default to false
  }

  // Update the value for "deleteLocalAfterUpload"
  static Future<void> setDeleteLocalAfterUpload(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deleteLocalAfterUploadKey, value);
  }
}
