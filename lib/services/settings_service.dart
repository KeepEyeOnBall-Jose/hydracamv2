import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _masterShouldRecordKey = 'masterShouldRecord';

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
}
